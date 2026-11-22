import Foundation

/// Drives the opt-in "use this resolver" flow on the DNS screen. Nothing is
/// applied until `apply()` runs from the confirmation sheet, and every call
/// shows the current and the pending servers first.
@MainActor
final class DNSResolverSwitchModel: ObservableObject {
    @Published private(set) var services: [String] = []
    @Published var selectedService = ""
    @Published private(set) var currentServers: [String] = []
    @Published private(set) var backup: DNSResolverBackup?
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    @Published var errorMessage: String?
    /// Non-nil while the confirmation sheet is open.
    @Published var pendingPlan: DNSResolverPlan?
    @Published var pendingApply = false

    private let service: DNSResolverSwitchService

    init(service: DNSResolverSwitchService = DNSResolverSwitchService()) {
        self.service = service
    }

    var currentLabel: String {
        currentServers.isEmpty
            ? String(localized: "Automatic (DHCP)")
            : currentServers.joined(separator: ", ")
    }

    func load() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            services = try await service.services()
            if !services.contains(selectedService) {
                selectedService = services.first ?? ""
            }
            backup = service.backup()
            if !selectedService.isEmpty {
                currentServers = try await service.currentServers(service: selectedService)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectService(_ name: String) async {
        selectedService = name
        isWorking = true
        defer { isWorking = false }
        do {
            currentServers = try await service.currentServers(service: name)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the confirmation sheet; no authorization is requested here.
    func prepare(servers: [String], name: String) {
        errorMessage = nil
        message = nil
        if let problem = DNSResolverSwitch.validate(servers) {
            errorMessage = problem
            return
        }
        guard !selectedService.isEmpty else {
            errorMessage = String(localized: "Choose a network service first.")
            return
        }
        pendingPlan = DNSResolverPlan(
            service: selectedService, currentServers: currentServers,
            newServers: servers, resolverName: name)
    }

    func prepareRevert() {
        guard let backup else {
            errorMessage = String(
                localized: "LanFi has not changed DNS on this Mac, so there is nothing to revert.")
            return
        }
        pendingPlan = DNSResolverPlan(
            service: backup.service,
            currentServers: currentServers,
            newServers: backup.servers,
            resolverName: String(localized: "the previous setting"))
    }

    func cancel() {
        pendingPlan = nil
    }

    func apply() async {
        guard let plan = pendingPlan else { return }
        pendingApply = true
        isWorking = true
        defer {
            pendingApply = false
            isWorking = false
        }
        do {
            try await service.apply(plan)
            pendingPlan = nil
            message =
                plan.isRevertToAutomatic
                ? String(localized: "DNS is back on DHCP.")
                : String(
                    format: String(localized: "DNS switched to %@ on %@."),
                    plan.resolverName, plan.service)
            backup = service.backup()
            currentServers =
                (try? await service.currentServers(service: plan.service)) ?? plan.newServers
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revert() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let plan = try await service.revert()
            pendingPlan = nil
            message = String(
                format: String(localized: "DNS restored on %@."), plan.service)
            backup = service.backup()
            selectedService = plan.service
            currentServers =
                (try? await service.currentServers(service: plan.service)) ?? plan.newServers
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
