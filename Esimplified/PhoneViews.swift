#if os(iOS)
import SwiftUI
import EsimplifiedKit

/// The iPhone/iPad screen: today's revenue preview + connection settings.
struct PhoneRoot: View {
    @Bindable var model: AppModel
    @State private var host = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                if let vm = model.viewModel {
                    Section("Today") {
                        RevenueDisplay(viewModel: vm, large: false)
                            .task { await vm.refresh() }
                    }
                }
                Section("Connection") {
                    TextField("Admin host (https://…)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                    Button("Save") {
                        model.save(host: host.trimmingCharacters(in: .whitespaces),
                                   token: token.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(host.isEmpty || token.isEmpty)
                }
                Section {
                    Text("Add the eSimplified widget to your Home or Lock Screen for a glanceable number.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("eSimplified")
            .onAppear {
                host = model.credentials?.host ?? ""
                token = model.credentials?.token ?? ""
            }
        }
    }
}
#endif
