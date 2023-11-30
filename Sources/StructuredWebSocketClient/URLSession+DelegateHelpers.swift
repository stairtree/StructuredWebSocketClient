import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// N.B.: Most of the delegate methods are commented out at the moment, as URLSession can sometimes change its
/// behavior just based on whether or not the delegate has implementations, even if those implementations behave
/// identically to how their absence would. Only the ones we currently use are enabled for now.

/// A protocol Swift types may conform to in order to receive `URLSession` delegate events. Does not require
/// conformance to `NSObject`.
protocol SimpleURLSessionTaskDelegate: Sendable {
    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError: Error?)
    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?)
    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?)
//    func urlSession(_: URLSession, task: URLSessionTask, willBeginDelayedRequest: URLRequest) async -> (URLSession.DelayedRequestDisposition, URLRequest?)
//    func urlSession(_: URLSession, taskIsWaitingForConnectivity: URLSessionTask)
//    func urlSession(_: URLSession, task: URLSessionTask, willPerformHTTPRedirection: HTTPURLResponse, newRequest: URLRequest) async -> URLRequest?
//    func urlSession(_: URLSession, task: URLSessionTask, didReceive: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)
//    func urlSession(_: URLSession, needNewBodyStreamForTask: URLSessionTask) async -> InputStream?
//    func urlSession(_: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
//    func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting: URLSessionTaskMetrics)
}

/// This extension provides default implementations for all delegate methods available on
/// ``SimpleURLSessionTaskDelegate``, mimicking the default behavior provided by the
/// legacy protocol when optional methods are omitted.
extension SimpleURLSessionTaskDelegate {
    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {}
    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {}
    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?) {}
//    func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting: URLSessionTaskMetrics) {}
//    func urlSession(_: URLSession, task: URLSessionTask, willBeginDelayedRequest: URLRequest) async -> (URLSession.DelayedRequestDisposition, URLRequest?) {
//        (.continueLoading, nil)
//    }
//    func urlSession(_: URLSession, taskIsWaitingForConnectivity: URLSessionTask) {}
//    func urlSession(_: URLSession, task: URLSessionTask, willPerformHTTPRedirection: HTTPURLResponse, newRequest: URLRequest) async -> URLRequest? { nil }
//    func urlSession(_: URLSession, task: URLSessionTask, didReceive: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
//        (.performDefaultHandling, nil)
//    }
//    func urlSession(_: URLSession, needNewBodyStreamForTask: URLSessionTask) async -> InputStream? { nil }
//    func urlSession(_: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {}
}

/// An adapter which bridges the gap between the legacy `URLSessionWebSocketDelegate` et al protocols and the
/// preferred ``SimpleURLSessionWebSocketDelegate`` protocol.
///
/// All delegate methods are directly forwarded. This adapter is designed to accomodate a "receiving" delegate
/// which is a reference type, to ensure that an explicitly weak reference may be taken.
final class URLSessionDelegateAdapter<D: SimpleURLSessionTaskDelegate & AnyObject>: NSObject, URLSessionWebSocketDelegate {
    private weak var realDelegate: D?

    init(adapting realDelegate: D) {
        self.realDelegate = realDelegate
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.realDelegate?.urlSession(session, task: task, didCompleteWithError: error)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.realDelegate?.urlSession(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.realDelegate?.urlSession(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
    }
//    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest) async -> (URLSession.DelayedRequestDisposition, URLRequest?) {
//        await self.realDelegate?.urlSession(session, task: task, willBeginDelayedRequest: request) ?? (.continueLoading, nil)
//    }
//    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
//        self.realDelegate?.urlSession(session, taskIsWaitingForConnectivity: task)
//    }
//    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
//        await self.realDelegate?.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request)
//    }
//    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
//        await self.realDelegate?.urlSession(session, task: task, didReceive: challenge) ?? (.performDefaultHandling, nil)
//    }
//    func urlSession(_ session: URLSession, needNewBodyStreamForTask task: URLSessionTask) async -> InputStream? {
//        await self.realDelegate?.urlSession(session, needNewBodyStreamForTask: task)
//    }
//    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
//        self.realDelegate?.urlSession(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
//    }
//    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
//        self.realDelegate?.urlSession(session, task: task, didFinishCollecting: metrics)
//    }
}
