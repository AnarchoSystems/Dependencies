import XCTest
import Dependencies

final class DependenciesTests: XCTestCase {
    
    @MainActor
    func testExample() throws {
        
        let order : EventOrder
        
        do
        {
           let env = Dependencies()
            env.register(component: Foo.self)
            env.register(component: Bar.self)
            env.register(component: EventOrder.self)
            
            let foo = try env.resolve(Foo.self)
            let bar = try env.resolve(Bar.self)
            XCTAssert(foo.bar === bar)
            XCTAssert(bar.foo === foo)
            
            order = try env.resolve()
        }
        
        XCTAssertEqual(order.events, [.orderBoots, .fooBoots, .barBoots, .barDestroys, .fooDestroys, .orderDestroys])
        
    }
}

enum Event {
    case orderBoots, fooBoots, barBoots, barDestroys, fooDestroys, orderDestroys
}

class EventOrder : Component {
    typealias Interface = EventOrder
    var events : [Event] = []
    required init() {}
    func boot() {
        events.append(.orderBoots)
    }
    func destroy() {
        events.append(.orderDestroys)
    }
}

class Foo : Component {
    typealias Interface = Foo
    @Injected var eventOrder : EventOrder
    @Injected(refOnly: true) var bar : Bar
    required init() {}
    func boot() {
        eventOrder.events.append(.fooBoots)
    }
    func destroy() {
        eventOrder.events.append(.fooDestroys)
    }
}

class Bar : Component {
    typealias Interface = Bar
    @Injected var eventOrder : EventOrder
    @Injected var foo : Foo
    required init() {}
    func boot() {
        eventOrder.events.append(.barBoots)
    }
    func destroy() {
        eventOrder.events.append(.barDestroys)
    }
}
