// The URLSession delegate: refusing redirects when asked to.

import Foundation

/// The delegate of every request BwLite makes (`VWTrust` adds the certificate handling on a Mac). It can refuse to
/// follow redirects: the answer is then the redirect itself, and no other site is contacted.
nonisolated class VWSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(followRedirects ? request : nil)
    }
}
