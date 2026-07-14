import SwiftUI
import Observation
import MapKit

// MARK: - 定位 ViewModel

@Observable
final class LocationViewModel {
    var location: LocationInfo?
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let api = SmsForwarderAPI.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            location = try await api.queryLocation()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 定位视图

struct LocationView: View {
    @State private var vm = LocationViewModel()

    var body: some View {
        Form {
            if let loc = vm.location {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            Text(loc.address ?? "无地址")
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("地址")
                }

                Section("经纬度") {
                    infoRow("纬度", value: loc.latitude.map { String(format: "%.6f", $0) } ?? "-")
                    infoRow("经度", value: loc.longitude.map { String(format: "%.6f", $0) } ?? "-")
                }

                Section("时间") {
                    infoRow("定位时间", value: DateUtil.format(timestamp: loc.time))
                }

                Section("供应商") {
                    infoRow("Provider", value: providerText(loc.provider))
                }

                Section {
                    Button {
                        openInMaps(loc: loc)
                    } label: {
                        Label("在地图中打开", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(loc.latitude == nil || loc.longitude == nil)
                }
            } else if vm.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("查询中...")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ContentUnavailableViewCompat(
                        title: "暂无定位信息",
                        icon: "location.fill",
                        description: "点击下方刷新获取"
                    )
                    .padding(.vertical, 24)
                }
            }

            Section {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(vm.isLoading)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("定位")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await vm.refresh()
        }
        .alert("出错", isPresented: $vm.showError, actions: {
            Button("好") {}
        }, message: {
            Text(vm.errorMessage ?? "")
        })
        .onAppear {
            if vm.location == nil {
                Task { await vm.refresh() }
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func providerText(_ provider: String?) -> String {
        guard let p = provider else { return "未知" }
        switch p.lowercased() {
        case "gps": return "GPS"
        case "network": return "网络定位"
        case "passive": return "被动定位"
        case "fused": return "融合定位"
        default: return p
        }
    }

    private func openInMaps(loc: LocationInfo) {
        guard let lat = loc.latitude, let lng = loc.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = loc.address ?? "设备位置"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
}
