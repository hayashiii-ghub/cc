import SwiftUI

struct ShelfEmptyView: View {

    var body: some View {
        Text("Drop files, links, or text here.")
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
