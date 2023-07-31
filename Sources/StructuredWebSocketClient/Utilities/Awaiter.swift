public actor Awaiter {
    enum State {
        case waiting(waiters: [CheckedContinuation<Void, Never>])
        case ready
    }
    private var state: State = .waiting(waiters: [])
    
    public init() {}
    
    private func addToWaiters() async {
        switch state {
        case .ready:
            return
        case var .waiting(waiters: waiters):
            await withCheckedContinuation { cont in
                waiters.append(cont)
                state = .waiting(waiters: waiters)
            }
        }
    }
    
    public func trigger() {
        guard case .waiting(waiters: var waiters) = self.state else {
            fatalError("Triggering in invalid state")
        }
        
        if waiters.isEmpty {
            self.state = .ready
            return
        }

        while !waiters.isEmpty {
            let nextWaiter = waiters.removeFirst()
            self.state = .waiting(waiters: waiters)
            nextWaiter.resume()
        }
        state = .ready
    }
    
    public func awaitUntilTriggered<T>(_ block: @Sendable @escaping () async throws -> T) async rethrows -> T {
        await self.addToWaiters()
        return try await block()
    }
}
