@MainActor
public protocol Component {
    associatedtype Interface
    init()
    func boot() throws
    func destroy() throws
}

public extension Component {
    func boot() {}
    func destroy() {}
}

public protocol Dependency {
    associatedtype Value
    @MainActor
    static func create(from env: Dependencies) -> Value
}

public protocol BaseDependency : Dependency {
    associatedtype Value
    static var value : Value {get}
}

public extension BaseDependency {
    static func create(from env: Dependencies) -> Value {
        value
    }
}

enum BootState {
    case booting
    case booted
}

@MainActor
public final class Dependencies {
    public typealias Interface = Dependencies
    var bootStates : [String : BootState] = [:]
    var components : [String : any Component] = [:]
    var constants : [String : Any] = [:]
    var destroyers : [() throws -> Void] = []
    public init() {}
    public var onDestroyFailure : (Error) -> Void = {print($0)}
    deinit {
        for destroyer in destroyers.reversed() {
            do {
                try destroyer()
            }
            catch {
                onDestroyFailure(error)
            }
        }
    }
}

protocol Reader {
    @MainActor
    func read(_ env: Dependencies) throws
}

@propertyWrapper
public class Ask : Reader {
    weak var _wrapped : Dependencies?
    public init() {}
    public var wrappedValue : Dependencies {
        guard let result = _wrapped else {
            fatalError("Dependency not injected!")
        }
        return result
    }
    func read(_ env: Dependencies) throws {
        _wrapped = env
    }
}

@propertyWrapper
public class Constant<T> : Reader {
    let keyPath : KeyPath<Dependencies, T>
    public init(keyPath: KeyPath<Dependencies, T>) {
        self.keyPath = keyPath
    }
    var _wrapped : T?
    public var wrappedValue : T {
        guard let result = _wrapped else {
            fatalError("Dependency not injected!")
        }
        return result
    }
    func read(_ env: Dependencies) {
        _wrapped = env[keyPath: keyPath]
    }
}

@propertyWrapper
public class Injected<T : AnyObject> : Reader {
    var refOnly = false
    public init(refOnly: Bool = false) {
        self.refOnly = refOnly
    }
    weak var _wrapped : T?
    public var wrappedValue : T {
        guard let result = _wrapped else {
            fatalError("Dependency not injected!")
        }
        return result
    }
    func read(_ env: Dependencies) throws {
        _wrapped = try env.resolve(T.self, refOnly: refOnly)
    }
}

struct DependencyNotFound : Error {
    let dep : String
}

public extension Dependencies {
    
    func register<C : Component>(component: C) {
        guard component is C.Interface else {
            fatalError("Invalid Component \(String(describing: C.self)): type does not implement its interface!")
        }
        components[String(describing: C.Interface.self)] = component
    }
    
    func register<C : Component>(component: C.Type) {
        register(component: C())
    }
    
    func inject<T>(into obj: T) throws {
        var children = Array(Mirror(reflecting: obj).children)
        var idx = 0
        while children.indices.contains(idx) {
            if let child = children[idx].value as? Reader {
                try child.read(self)
            }
            else {
                children.append(contentsOf: Mirror(reflecting: children[idx].value).children)
            }
            idx += 1
        }
    }
    
    func resolve<I>(_ interface: I.Type = I.self, refOnly: Bool = false) throws -> I {
        let key = String(describing: interface)
        guard let component = components[key],
        let result = component as? I else {
            throw DependencyNotFound(dep: key)
        }
        if bootStates[key] == .booted || refOnly {
            return result
        }
        let wasBooting = bootStates[key] == .booting
        bootStates[key] = .booting
        if !wasBooting {
            try inject(into: result)
        }
        if bootStates[key] != .booted {
            try component.boot()
            destroyers.append(component.destroy)
            bootStates[key] = .booted
        }
        else if !refOnly {
            print("WARNING: unhandled circular dependency detected for dependency " + key + "! Consider using refOnly on one of your Injected dependencies.")
        }
        return result
    }
    
    subscript<Key : Dependency>(key: Key.Type) -> Key.Value {
        get {
            if constants[String(describing: key)] == nil {
                constants[String(describing: key)] = Key.create(from: self)
            }
            return constants[String(describing: key)] as! Key.Value
        }
        set {
            constants[String(describing: key)] = newValue
        }
    }
    
}

enum Debug : BaseDependency {
    static public var value: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

public extension Dependencies {
    var debug : Bool {
        self[Debug.self]
    }
}
