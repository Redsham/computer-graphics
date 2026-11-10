/// Fixed-capacity chronological storage with O(1) append and eviction.
/// Array snapshots are created only at API/UI boundaries.
struct BoundedHistory<Element>: RandomAccessCollection, MutableCollection {
    let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    init(capacity: Int) {
        self.capacity = Swift.max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    var startIndex: Int {
        0
    }
    var endIndex: Int {
        storage.count
    }

    subscript(position: Int) -> Element {
        get {
            precondition(indices.contains(position))
            return storage[(head + position) % capacity]
        }
        set {
            precondition(indices.contains(position))
            storage[(head + position) % capacity] = newValue
        }
    }

    func index(after index: Int) -> Int {
        index + 1
    }
    func index(before index: Int) -> Int {
        index - 1
    }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        storage.removeAll(keepingCapacity: keepingCapacity)
        head = 0
    }
}
