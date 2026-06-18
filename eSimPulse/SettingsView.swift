import SwiftUI
import EsimPulseKit

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var token: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection").font(.headline)
            TextField("Admin host (https://…)", text: $host)
            SecureField("Bearer token", text: $token)
            HStack {
                Spacer()
                Button("Save") {
                    model.save(host: host.trimmingCharacters(in: .whitespaces),
                               token: token.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(host.isEmpty || token.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            host = model.credentials?.host ?? ""
            token = model.credentials?.token ?? ""
        }
    }
}
