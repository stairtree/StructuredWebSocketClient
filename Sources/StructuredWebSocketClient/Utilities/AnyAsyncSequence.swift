
public struct AnyAsyncSequence<Element>: AsyncSequence {
    public typealias AsyncIterator = AnyAsyncIterator<Element>
    public typealias Element = Element

    let _makeAsyncIterator: @Sendable () -> AnyAsyncIterator<Element>

    public struct AnyAsyncIterator<E>: AsyncIteratorProtocol {
        public typealias Element = E

        private let _next: () async throws -> E?

        init<I: AsyncIteratorProtocol>(itr: I) where I.Element == E {
            var itr = itr
            self._next = {
                try await itr.next()
            }
        }

        public mutating func next() async throws -> E? {
            return try await _next()
        }
    }

    public init<S: AsyncSequence>(seq: S) where S.Element == Element {
        _makeAsyncIterator = {
            AnyAsyncIterator(itr: seq.makeAsyncIterator())
        }
    }

    public func makeAsyncIterator() -> AnyAsyncIterator<Element> {
        return _makeAsyncIterator()
    }
}

extension AsyncSequence {
    public func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Element> {
        AnyAsyncSequence(seq: self)
    }
}

// extension AnyAsyncSequence.AnyAsyncIterator: @unchecked Sendable where Element: Sendable {}
extension AnyAsyncSequence: Sendable where Element: Sendable {}
