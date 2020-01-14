import XCTest
import Vapor

@testable import RestClient

struct Book: Content {
    let name: String
    let pages: Int
}

struct TestClient: Client {
    
    let eventLoopGroup: EventLoopGroup
    
    init(app: Application) {
        self.eventLoopGroup = app.eventLoopGroup
    }
    
    func `for`(_ request: Request) -> Client {
        fatalError("You shouldn't do this")
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        do {
            var status = HTTPStatus.ok
            
            switch request.method {
            case .POST:
                break
            default:
                switch request.url.path {
                case "/ok":
                    break
                case "/accept-audio":
                    if !request.headers.accept.contains(where: { $0.mediaType.type == "audio" }) {
                        status = .notAcceptable
                    }
                    break
                case "/query":
                    var res = ClientResponse(status: .ok)
                    let query = try request.query.decode([String:String].self)
                    try! res.content.encode(query)
                    return eventLoopGroup.future(res)
                case "/books/existing":
                    var res = ClientResponse()
                    try! res.content.encode(Book(name: "Swift for Beginners", pages: 42))
                    return eventLoopGroup.future(res)
                case "/text":
                    var res = ClientResponse()
                    let text = "read me"
                    try! res.content.encode(text, as: .plainText)
                    return eventLoopGroup.future(res)
                default:
                    status = .notFound
                }
            }
            
            
            return eventLoopGroup.future(ClientResponse(status: status))
        }
        catch {
            return eventLoopGroup.future(ClientResponse(status: .internalServerError))
        }
    }

}

final class RestClientTests: XCTestCase {

    var app: Application!
    var client: RestClient!
    
    override func setUp() {
        super.setUp()
        
        app = Application()
        let testClient = TestClient(app: app)
        
        client = RestClient(client: testClient, hostUrl: URL(string: "https://example.com")!, eventLoop: app.eventLoopGroup.next())
        client.middleware = [
            StatusCodeToErrorTransformer()
        ]
    }

    func test_realClient() throws {
        let client = app.client
        let restClient = RestClient(client: client, hostUrl: URL(string: "https://example.com")!, eventLoop: app.eventLoopGroup.next())
        let (_, res) = try restClient.request(url: "/").wait()
        print(res)
    }
    
    func test_send() throws {
        let req = ClientRequest(method: .GET, url: "/ok")
        let res = try client.send(req).wait()
        XCTAssertEqual(res.status, .ok)
    }
    
    func test_middleware() throws {
        struct AddHeaderMiddleWare: RestClientMiddleware {
            func respond(to request: ClientRequest, chainingTo next: RestClientResponder) -> EventLoopFuture<ClientResponse> {
                var request = request
                request.headers.add(name: .accept, value: "audio/basic")
                return next.respond(to: request)
            }
        }
        
        client.middleware = [AddHeaderMiddleWare()]
        
        let req = ClientRequest(method: .GET, url: "/accept-audio")
        let res = try client.send(req).wait()
        XCTAssertEqual(res.status, .ok)
    }
    
    func test_200() throws {
        let (_, res) = try client.request(url: "/ok").wait()
        XCTAssertEqual(res.status, .ok)
    }
    
    func test_404() throws {
        do {
            _ = try client.request(url: "/undefined").wait()
            XCTFail("call should throw")
        }
        catch {
            switch error {
            case let error as ClientRequestError:
                XCTAssertEqual(error.status, .notFound)
            default:
                XCTFail("error should be instance of \(ClientRequestError.self)")
            }
        }
    }

    func test_query() throws {
        let url = "/query"
        let query = [
            "filter": "name = 'John&Me' and age = 42",
            "count": "2",
        ]
        let result = try client.request(url: url, query: query, as: [String:String].self).wait()
        XCTAssertEqual(query, result)
    }
    
    func test_getExistingJsonResource() throws {
        let book = try client.request(url: "/books/existing", as: Book.self).wait()
        XCTAssertEqual(book.name, "Swift for Beginners")
        XCTAssertEqual(book.pages, 42)
    }

    func test_getNonExistingJsonResourceWithErrorTransformer() throws {
        let book = try client.request(url: "/books/non-existing", as: Book?.self).wait()
        XCTAssertNil(book)
    }

    func test_getNonExistingJsonResourceWithoutErrorTransformer() throws {
        client.middleware = []
        let book = try client.request(url: "/books/non-existing", as: Book?.self).wait()
        XCTAssertNil(book)
    }

    func test_getTextUsing_get() throws {
        let text = try client.request(url: "/text", as: String.self).wait()
        XCTAssertEqual(text, "read me")
    }
    
    func test_getTextUsing_request() throws {
        let text = try client.request(url: "/text", as: String.self).wait()
        XCTAssertEqual(text, "read me")
    }
    
//    func test_post() throws {
//        let book = Book(name: "A History of Gallifrey", pages: 13)
//        let response = try client.request(method: .POST, url: "/books", json: book).wait()
//        print(response)
////        XCTAssertEqual(text, "read me")
//    }
    
//    static let allTests = [
//        ("test_200", test_200),
//        ("test_404", test_404),
//        ("test_query", test_query),
//        ("test_getNonExistingJsonResourceWithErrorTransformer", test_getNonExistingJsonResourceWithErrorTransformer),
//        ("test_getNonExistingJsonResourceWithoutErrorTransformer", test_getNonExistingJsonResourceWithoutErrorTransformer),
//    ]
//
}
