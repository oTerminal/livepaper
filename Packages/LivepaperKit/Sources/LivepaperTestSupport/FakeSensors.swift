import LivepaperCore
import LivepaperSystem

/// A sensor that reports whatever it is told to, to every stream made from it.
///
/// One generic fake stands in for every sensor; the names below say which.
@MainActor
public final class FakeSensor<Value: Sendable> {
    private let broadcast: Broadcast<Value>

    /// A sensor of a state, which starts at `initial` and gives each new stream the latest value.
    public init(_ initial: Value) {
        broadcast = Broadcast()
        broadcast.send(initial)
    }

    /// A sensor of events, which gives a new stream only what happens after it is made.
    public init() {
        broadcast = Broadcast(replaysLatest: false, bufferingPolicy: .unbounded)
    }

    public func updates() -> AsyncStream<Value> {
        broadcast.stream()
    }

    /// Reports a value, as the system would.
    public func send(_ value: Value) {
        broadcast.send(value)
    }

    public var latest: Value? { broadcast.latest }

    /// How many streams are being read: a sensor with none observes nothing.
    public var readerCount: Int { broadcast.readerCount }
}

public typealias FakeDisplaySensor = FakeSensor<[ConnectedDisplay]>
public typealias FakePowerSensor = FakeSensor<PowerState>
public typealias FakeLockSensor = FakeSensor<Bool>
public typealias FakeSleepSensor = FakeSensor<SystemSleepEvent>
public typealias FakeDisplaySleepSensor = FakeSensor<Set<DisplayIdentity>>
public typealias FakeCoveredDisplaySensor = FakeSensor<Set<DisplayIdentity>>

extension FakeSensor: DisplaySensor where Value == [ConnectedDisplay] {}
extension FakeSensor: PowerSensor where Value == PowerState {}
extension FakeSensor: LockSensor where Value == Bool {}
extension FakeSensor: SleepSensor where Value == SystemSleepEvent {}
extension FakeSensor: DisplaySleepSensor, CoveredDisplaySensor where Value == Set<DisplayIdentity> {}
