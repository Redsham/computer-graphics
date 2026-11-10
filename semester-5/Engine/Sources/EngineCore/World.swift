// MARK: - Entity identity

public struct Entity: Hashable, Sendable {
    public let index: Int
    public let generation: UInt64
}

// MARK: - Component storage

@MainActor private protocol ErasedStorage: AnyObject {
    func remove(_ entity: Entity)
}

@MainActor private final class ComponentStorage<C>: ErasedStorage {
    var values: [Entity: C] = [:]

    func remove(_ entity: Entity) {
        values.removeValue(forKey: entity)
    }
}

/// All structural edits during a system update go through deferMutation.
@MainActor public final class World {
    private var generations: [UInt64] = []
    private var alive: Set<Int> = []
    private var free: [Int] = []
    private var storages: [ObjectIdentifier: any ErasedStorage] = [:]
    private var deferred: [(World) -> Void] = []
    private var updating = false

    public init() {}

    // MARK: - Entity lifecycle

    public func isAlive(_ entity: Entity) -> Bool {
        alive.contains(entity.index) && generations[entity.index] == entity.generation
    }

    @discardableResult public func create() -> Entity {
        precondition(!updating, "Use deferMutation for structural changes inside systems")
        let index: Int

        if let reused = free.popLast() {
            index = reused
        } else {
            index = generations.count
            generations.append(0)
        }

        alive.insert(index)
        return Entity(index: index, generation: generations[index])
    }

    public func destroy(_ entity: Entity) {
        precondition(!updating, "Use deferMutation for structural changes inside systems")

        guard isAlive(entity) else {
            return
        }

        for storage in storages.values {
            storage.remove(entity)
        }

        alive.remove(entity.index)
        generations[entity.index] &+= 1
        free.append(entity.index)
    }

    // MARK: - Components

    public func set<C>(_ component: C, for entity: Entity) {
        guard isAlive(entity) else {
            return
        }

        let storage: ComponentStorage<C> = storageFor(C.self)
        precondition(
            !updating || storage.values[entity] != nil, "Defer component insertion inside systems")
        storage.values[entity] = component
    }

    public func get<C>(_ type: C.Type, for entity: Entity) -> C? {
        guard isAlive(entity) else {
            return nil
        }

        return (storages[ObjectIdentifier(type)] as? ComponentStorage<C>)?.values[entity]
    }

    public func remove<C>(_ type: C.Type, from entity: Entity) {
        precondition(!updating, "Defer component removal inside systems")
        (storages[ObjectIdentifier(type)] as? ComponentStorage<C>)?.remove(entity)
    }

    public func entities<C>(with type: C.Type) -> [Entity] {
        let keys = (storages[ObjectIdentifier(type)] as? ComponentStorage<C>)?.values.keys
        return keys.map(Array.init)?.sorted { $0.index < $1.index } ?? []
    }

    // MARK: - Deferred mutations

    public func deferMutation(_ action: @escaping (World) -> Void) {
        deferred.append(action)
    }

    func beginUpdate() {
        precondition(!updating)
        updating = true
    }

    func endUpdate() {
        updating = false
        let actions = deferred
        deferred.removeAll(keepingCapacity: true)

        for action in actions {
            action(self)
        }
    }

    // MARK: - Storage lookup

    private func storageFor<C>(_ type: C.Type) -> ComponentStorage<C> {
        let key = ObjectIdentifier(type)

        if let storage = storages[key] as? ComponentStorage<C> {
            return storage
        }

        let storage = ComponentStorage<C>()
        storages[key] = storage
        return storage
    }
}
