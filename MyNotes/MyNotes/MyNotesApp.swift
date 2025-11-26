import SwiftUI

struct Note: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
}

class NotesViewModel: ObservableObject {
    @Published var notes: [Note] {
        didSet {
            if let encoded = try? JSONEncoder().encode(notes) {
                UserDefaults.standard.set(encoded, forKey: "notes")
            }
        }
    }
    
    init() {
        if let savedNotes = UserDefaults.standard.data(forKey: "notes"),
           let decodedNotes = try? JSONDecoder().decode([Note].self, from: savedNotes) {
            self.notes = decodedNotes
        } else {
            self.notes = []
        }
    }
    
    func addNote(title: String, content: String) {
        let newNote = Note(title: title, content: content)
        notes.append(newNote)
    }
    
    func deleteNote(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = NotesViewModel()
    @State private var showAddNote = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.notes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        Text(note.title)
                            .font(.headline)
                    }
                }
                .onDelete(perform: viewModel.deleteNote)
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddNote = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddNote) {
                AddNoteView(viewModel: viewModel)
            }
        }
    }
}

struct NoteDetailView: View {
    let note: Note
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(note.content)
                .padding()
            Spacer()
        }
        .navigationTitle(note.title)
    }
}

struct AddNoteView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: NotesViewModel
    @State private var title = ""
    @State private var content = ""
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $content)
                    .frame(height: 200)
            }
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if !title.isEmpty && !content.isEmpty {
                            viewModel.addNote(title: title, content: content)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
    }
}

@main
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
