import SwiftUI
import AppKit

struct LaunchpadSearchBar: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    @State private var inputTimer: Timer?
    
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white)
                    .font(.system(size: 16))

                TextField("", text: $query)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .placeholder(when: query.isEmpty && !focused) {
                        Text("Search")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    }
            }
            .frame(width: 250, height: 34)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.3))
            )
            .onTapGesture { focused = true }
            .onChange(of: query) { _ in resetInputTimer() }
            .onChange(of: focused) { newValue in
                if newValue {
                    resetInputTimer()
                } else {
                    inputTimer?.invalidate()
                    inputTimer = nil
                }
            }
            Spacer(minLength: 0)
        }
    }
    
    private func resetInputTimer() {
        inputTimer?.invalidate()
        inputTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async { focused = false }
        }
    }
}

// MARK: - 占位符支持
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder()
                .opacity(shouldShow ? 1 : 0)
                .allowsHitTesting(false)
            self
        }
    }
}

