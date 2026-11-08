import AppKit

// Fork: a tab's menu acts on every tab picked in the column (⌘- or
// ⇧-click), when the one right-clicked is among them — not only Close and
// Move to Space, as upstream has it, but grouping, pinning, moving to a
// window, duplicating, copying, muting and putting to sleep too. Right-clicked
// outside the selection, it is that tab alone, as before.
//
// A pinned tab can go into a group too: it is unpinned on the way in, as a
// group is a place kept of its own (it stays through Clear).

extension Browser {
    /// The tabs a menu item opened on `tab` is for.
    func many(_ tab: Tab) -> [Tab] { pickedOrOnly(tab) }

    /// How many: for the menu's labels.
    func manyCount(_ tab: Tab) -> Int { many(tab).count }

    /// "Pin" or "Pin 3 Tabs".
    func manyLabel(_ verb: String, _ tab: Tab) -> String {
        let count = manyCount(tab)
        return count > 1 ? "\(verb) \(count) Tabs" : verb
    }

    /// Into a group (nil: out of one), every one of them; a new group made
    /// for them when `id` is nil and `new` is true.
    func group(_ tab: Tab, into id: UUID?, new: Bool = false) {
        let going = many(tab).filter { !$0.shy && !$0.bench }
        guard !going.isEmpty else { return }
        TabUndo.step(self) {
            for each in going where each.pin != nil && (new || id != nil) { unpin(each) }
            if new {
                let made = addTabGroup(containing: going[0])
                for each in going.dropFirst() { move(each, toGroup: made) }
            } else {
                for each in going { move(each, toGroup: id) }
            }
        }
    }

    /// Whether Move to Group has anything to offer for them.
    func groupable(_ tab: Tab) -> Bool {
        many(tab).contains { !$0.shy && !$0.bench }
    }

    func pinMany(_ tab: Tab, listed: Bool = false) {
        TabUndo.step(self) { for each in many(tab) where each.pin == nil && each.isWeb && !each.shy { pin(each, listed: listed) } }
    }

    func unpinMany(_ tab: Tab) {
        TabUndo.step(self) { for each in many(tab) where each.pin != nil { unpin(each) } }
    }

    func deleteMany(_ tab: Tab) {
        let going = many(tab).filter { $0.pin != nil }
        TabUndo.step(self) {
            for each in going {
                unpin(each)
                close(each)
            }
        }
    }

    func listMany(_ tab: Tab, _ listed: Bool) {
        TabUndo.step(self) { for each in many(tab) where each.pin != nil { setListed(each, listed) } }
    }

    func everywhereMany(_ tab: Tab, _ everywhere: Bool) {
        for each in many(tab) where each.pin != nil && each.everywhere != everywhere {
            if everywhere { shareEverywhere(each) } else { keepHere(each) }
        }
    }

    /// Into another window of this profile, or a new one: all of them
    /// together, the first making the new window.
    func moveManyToWindow(_ tab: Tab, _ target: Browser?) {
        let going = many(tab).filter { $0.pin == nil && !$0.bench }
        guard let first = going.first else { return }
        clearTabSelection()
        moveToWindow(first, target)
        let destination = target ?? Browsers.all.first { $0 !== self && $0.tabs.contains { $0.id == first.id } }
        guard let destination else { return }
        for each in going.dropFirst() { moveToWindow(each, destination) }
    }

    func duplicateMany(_ tab: Tab) {
        let going = many(tab).filter(\.isWeb)
        for each in going {
            guard let url = each.address else { continue }
            open(url, foreground: going.count == 1, from: each)
        }
    }

    func copyMany(_ tab: Tab, as kind: CopyKind) {
        let going = many(tab).filter(\.isWeb)
        guard going.count > 1 else {
            select(tab)
            switch kind {
            case .address: copyAddress()
            case .markdown: copyMarkdownLink()
            case .clean: copyCleanLink()
            }
            return
        }
        let lines = going.compactMap { each -> String? in
            guard let url = each.address else { return nil }
            switch kind {
            case .address: return url.absoluteString
            case .markdown: return Browser.markdownLink(each.label, url)
            case .clean: return CleanLink.clean(url).absoluteString
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        announce("\(lines.count) links copied")
    }

    enum CopyKind { case address, markdown, clean }

    /// Muted or not, all of them as the one right-clicked is going.
    func muteMany(_ tab: Tab) {
        let mute = !tab.muted
        for each in many(tab) where each.muted != mute { each.toggleMute() }
    }

    func sleepMany(_ tab: Tab) {
        let going = many(tab)
        guard going.count > 1 else {
            sleep(tab) { [weak self] outcome in
                if outcome != "asleep" { self?.announce("Stays awake: \(outcome)") }
            }
            return
        }
        for each in going where awake(because: each) == nil { sleep(each) }
    }

    /// Everything but them.
    func closeOthersMany(_ tab: Tab) {
        let keep = many(tab)
        guard keep.count > 1 else { return closeOthers(but: tab) }
        let kept = Set(keep.map(\.id))
        let partners = Set(keep.compactMap { split(for: $0)?.partner(of: $0.id) })
        clearTabSelection()
        if let active, !kept.contains(active.id) { select(tab) }
        for each in tabs.filter({ !kept.contains($0.id) && !partners.contains($0.id) }) { close(each) }
    }
}
