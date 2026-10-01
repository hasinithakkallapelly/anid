import SwiftUI

struct GoalPicker: View {
    let goals: [Goal]
    @Binding var selection: Goal?

    var body: some View {
        Picker(selection: $selection) {
            Text("None").tag(nil as Goal?)
            ForEach(goals) { goal in
                Text(goal.title).tag(Optional(goal))
            }
        } label: {
            Label("Goal", systemImage: "target")
        }
    }
}
