CleanTree v1.1.0-beta6

Shopping Lists visual/readability hotfix:
- Restores Shopping Lists to CleanTree's black/charcoal panel palette instead of brown/gold backgrounds.
- Import/Export now has a clearly labeled, bordered black text-entry well so it is obvious where to paste/copy CTSL1 strings.
- Import immediately focuses the text-entry area and positions the cursor at the start.
- Auto-purchase completion details are sent to chat while the in-window status remains short, preventing header text overlap.
- Widens the normal CleanTree status line to reduce wrapping.

CleanTree v1.1.0-beta5

Shopping Lists mouse-input hotfix:
- Shopping Lists now uses FULLSCREEN_DIALOG strata with sane frame levels instead of very large legacy frame levels.
- The window is hosted on UIParent for reliable mouse ownership, while existing lifecycle hooks still close it with Progression/CleanTree.
- Shopping List panels and controls use explicit dialog levels so underlying Progression frames cannot intercept clicks.
- Shopping List backgrounds now use a solid texture for much better contrast/readability.

CleanTree v1.1.0-beta3

Shopping Lists UI hotfix:
- Shopping Lists is now parented to CleanTree instead of UIParent, so it follows /progression visibility.
- Closing Progression or restoring the native Skill Tree closes Shopping Lists and its Import/Export window.
- Shopping Lists is explicitly raised above the CleanTree pane so buttons receive mouse clicks.
- Shopping List backgrounds are brighter and fully opaque for better readability.

CleanTree v1.1.0-beta2

Buyable Now beta:
- Adds a one-click Buyable Now header button beside Shopping Lists.
- Shows only nodes that are currently unlocked by prerequisites and affordable with the player's live Soul Ash balance.
- Recalculates after staged purchases, so newly unlocked/affordable nodes appear immediately and spent nodes disappear.
- Uses the same EbonAPI prerequisite authority and native staged Soul Ash state as normal CleanTree purchasing.
- Includes Endless nodes only when their next rank is genuinely available and affordable.

Shopping Lists beta:
- Adds exact ordered Shopping Lists for finite Skill Tree purchases.
- Includes Full Tree Order, Damage First, Survival First, Convenience First, Balanced, and Cheapest First starter lists.
- Auto-purchase treats list order as a live priority queue: locked/unaffordable entries are skipped temporarily and priority #1 is retried after every successful purchase.
- Auto-purchase stages native Ebonhold purchases only and never clicks Apply Changes for the player.
- Adds New, Copy, Rename, Delete, Append Missing, node search/add, and exact Top/Up/Down/Bottom ordering controls.
- Adds versioned single-string export/import using exact node IDs: CTSL1:<name>:<ordered IDs>.
- Imported lists are created immediately and selected as the active Shopping List.
- Endless nodes are intentionally excluded from Shopping Lists.

CleanTree v1.0.0

First public release:
- Promotes the tested hotfix44 implementation to the first public CleanTree release.
- Requires EbonAPI 1.0+ as a separately installed addon.
- Replaces Project Ebonhold's giant Soul Ash Skill Tree graph with a compact list/detail interface inside the native Progression window.
- Supports All, Unowned, Damage, Survival, Convenience, Endless, Cart, and Purchased views.
- Uses EbonAPI's Talent Database and prerequisite graph for stable ordering and structural availability.
- Uses server-committed loadout state for Purchased vs staged changes.
- Stages purchases through the native Skill Tree, supports cart removal, and applies through Ebonhold's native Apply Changes path.
- Preserves an escape hatch in both directions: Restore Native Skill Tree / Restore CleanTree UI.
- Includes diagnostic slash commands for troubleshooting EbonAPI and native-tree integration.

Development history follows.

CleanTree v0.0.1-hotfix44

EbonAPI migration (phase 1):
- CleanTree now requires EbonAPI 1.0+ as a separate installed addon (not bundled).
- Uses EbonAPI's live ProjectEbonhold TalentDatabase for node definitions, prerequisite links, finite max ranks, and Endless growth/cost data.
- Uses EbonAPI's stable skillTreeNode<ID> mapping for fast direct binding instead of scanning the full native canvas when the database is ready.
- Uses SkillTreeFrame.pointsText through EbonAPI for the immediate staged Soul Ash balance, with SERVER_ASH as a fallback before the native footer populates.
- Uses SERVER_LOADOUT for committed ranks, so Purchased can distinguish server-committed nodes from ranks that are only staged in the native tree.
- Endless rank reads come from the native stack badge and Endless next-cost calculation comes from soulPointsCosts + infiniteGrowth, capped at 100,000,000 Soul Ash. No tooltip hover is required for rank/cost.
- Availability checks prefer EbonAPI's live prerequisite graph; the captured web graph remains only as a defensive fallback/order snapshot.
- Adds /cleantree apiprobe for EbonAPI feature/state diagnostics, including all three Endless ranks and next costs.
- SkillTreeAutoLoad is NOT required and is not bundled; CleanTree only uses the shared EbonAPI contract so the two addons can coexist.

Installation note:
- Install and enable EbonAPI 1.0+ in Interface/AddOns/EbonAPI before enabling CleanTree. WoW will load EbonAPI first because CleanTree declares it as a dependency.

CleanTree v0.0.1-hotfix43

Hotfix43:
- Uses Project Ebonhold's directed prerequisite graph for AVAILABLE / NOT AVAILABLE state.
- Multiple incoming links are treated as AND prerequisites, matching join nodes in the native tree.
- Endless prefers skillTreeNode2000/2001/2002 directly and reads the bare stack overlay (50, 67, ...).
- Endless at stack 50+ falls back to the observed live 100,000,000 Soul Ash cap if synthetic native tooltip generation fails.
- Keeps repeated Endless staging: each + is one rank and the node never becomes MAXED.

CleanTree v0.0.1-hotfix41

Native UI toggle + stricter unlock ordering:
- Adds a "Restore Native Skill Tree" button beside Refresh in the CleanTree header.
- Native mode fully restores Ebonhold's stock node canvas/footer and shows a small "Restore CleanTree UI" button in the native tree viewport.
- The chosen native/CleanTree mode persists when switching Progression tabs or reopening the Skill Tree.
- Refines Project Ebonhold JSON ordering from a generic topological traversal to strict prerequisite depth: root -> all immediately unlocked nodes -> depth 2 -> depth 3, etc.
- Same-depth nodes use the web builder's position for stable left-to-right ordering; every prerequisite still appears before every dependent node.
- /cleantree orderprobe now prints the ordering mode.

CleanTree v0.0.1-hotfix40

Exact prerequisite ordering:
- Replaces the geometric approximation with the directed prerequisite graph from Project Ebonhold's own skill-tree.json.
- All 813 finite nodes map 1:1 to the existing CleanTree static IDs; the website data also contains the same three Endless IDs (2000-2002).
- Uses a precomputed stable topological traversal: a node can never sort before any prerequisite. Geometry is used only offline as a tie-breaker between simultaneously-unlocked branches.
- No graph traversal or frame-coordinate work runs during normal in-game filtering/search/scrolling.
- /cleantree orderprobe now reports the exact graph source, root IDs, depth, and static IDs.

CleanTree v0.0.1-hotfix39

Diagnostic: adds /cleantree graphprobe <node name> to inspect native rank/spell tables, click-handler upvalues, connector regions/children, and graph-like globals. No ordering/purchase behavior changes from hotfix38.

CleanTree v0.0.1-hotfix37
Hotfix34 first-load list repair:
- Clamps the FauxScrollFrame offset whenever filtering shrinks the node list, preventing a stale offset from rendering an apparently empty list.
- Adds a lightweight self-heal: if CleanTree reports filtered nodes but no row is actually visible after loading, it automatically resets to the top and repaints instead of requiring a manual tab switch.
- No purchase, cart, layout, border, or loading-performance behavior changed.

Hotfix32 Pending Changes layout fix:
- Gives the descriptive Pending Changes text and the numeric spend summary hard, non-overlapping vertical regions.
- Removes the extra empty-state instruction line that was colliding with the spend summary on shorter layouts.

CleanTree v0.0.1-hotfix31
Hotfix31 layout polish:
- Gives Search its own anchored space after Purchased; category buttons are slightly narrower so the two can never overlap.
- Removes the excessive left gutter by docking CleanTree almost flush to the native skill-tree viewport.
- Shrinks the detail panel slightly and gives Pending Changes a dedicated fixed footer band, preventing the title/body/summary text from stacking on top of itself.

CleanTree v0.0.1-hotfix30
Hotfix30 visual integration:
- CleanTree root is transparent so the native brown Progression background shows between CleanTree panels.
- Content is inset slightly from the native scroll viewport to clear the upper-left portrait/header edge.
- CleanTree now extends to the bottom of skillTreeFrame (not the hidden native footer), consuming the empty strip above the Progression tabs.
- Native blue progress/header chrome and bottom Progression tabs remain owned by Ebonhold.
- Native CollectionsJournal owns the outer border/portrait/title; CleanTree no longer draws a competing outer border.
- Keeps the native blue progress bar/header area exposed and starts the CleanTree pane below it.
- Force-suppresses only skillTreeScroll/skillTreeCanvas and skillTreeBottomBar, including the native Soul Ash, Apply Changes, and search footer.
- Periodically reasserts those two native suppressions so Ebonhold cannot resurrect footer artifacts after refresh/minimize/apply.

CleanTree v0.0.1-hotfix28

- Uses skillTreeScroll as the authoritative native viewport instead of filling all of skillTreeFrame.
- Keeps CollectionsJournal title/portrait/close/side chrome outside CleanTree's rectangle.
- Extends CleanTree through skillTreeBottomBar so the stock Soul Ash / Apply / Search footer stays replaced.
- Suppresses only skillTreeScroll (nodes + native scrollbar) and skillTreeBottomBar instead of recursively blanking every child of skillTreeFrame.
- Reduces CleanTree's frame-level offset from +100 to +5 to avoid covering native sibling chrome.
- FrameProbe now reports skillTreeScroll explicitly.

CleanTree v0.0.1-hotfix25

- Integrates CleanTree to the full native Skill Tree content rectangle while preserving Ebonhold's native title/close control and bottom Progression tabs.
- Covers the stock blue progress bar and native Soul Ash / Apply / Search footer instead of leaving them visible behind CleanTree.
- Suppresses only the large native Skill Tree medallion at the upper-left corner; does not hide the outer Progression shell or bottom tabs.

CleanTree v0.0.1-hotfix24

Hotfix21 changes:
- Adds a blocking LOADING CLEANTREE overlay while native discovery, full finite-node binding/ownership resolution, and effect scanning complete.
- Stops rendering/reordering the node list during lazy discovery; the usable list appears only after node state is stable.
- Adds a full incremental finite-node resolve pass before the UI becomes interactive, avoiding purchased nodes jumping in/out as visible rows lazily bind.
- Restores click-drag movement through the native Skill Tree frame.
- Hides the FauxScrollFrame scrollbar chrome and adds mouse-wheel scrolling.
- Expands the reusable row pool; the existing height calculation decides how many rows actually fit, reducing dead space without overflowing the inner panel.

CleanTree v0.0.1-hotfix20

Hotfix19 changes:
- Suppresses the remaining native Skill Tree top chrome from the Progression-frame ancestors, including the round top-left icon, native Skill Tree title/top border, and stock top-right control while CleanTree is active.
- Keeps bottom Progression tabs untouched and restores all suppressed native chrome when CleanTree closes/switches away.
- Fixes Unowned/branch filtering when ownership is learned lazily: PURCHASED/MAXED rows are hidden immediately and the list re-filters on the next tick.
- Makes Cart removal use Ebonhold's actual RightButton OnClick path first instead of relying on Button:Click("RightButton"), which is unreliable on this 3.3.5 client.
- Adds fallback right-click targets inside the bound native node before declaring a staged rank non-removable.

CleanTree v0.0.1-hotfix15

Built directly from the known-good rebase7 baseline.

Hotfix12 changes:
- Adds Unowned immediately after All and makes Unowned the default tab.
- Renames Owned to Purchased and places Purchased at the end.
- All now truly shows all nodes; branch tabs remain focused on unfinished nodes.
- Reduces visible row widgets from 9 to 8 so the list stays inside its inner panel.
- Stops hiding the outer skillTreeFrame; only the native tree canvas/footer are visually suppressed.
- Hooks the Skill Tree canvas first so switching to Echoes/Transmog/Mounts/Companions/Prestige hides CleanTree instead of hijacking the whole Progression window.
- No Endless/discard/purchase-path changes in this build.

CleanTree v0.0.1-rebase7

Hotfix7 changes:
- Docks CleanTree directly over Ebonhold's native Skill Tree frame so the skin replaces it in-place instead of floating beside it.
- Removes dragging; the replacement follows the native Skill Tree frame automatically.
- Adds an Owned tab. Completed finite nodes stay out of normal browsing and are collected there for reference.
- Fixes the + buttons doing nothing: tooltip-poll code was accidentally inserted inside stageNode and referenced an undefined elapsed value, aborting every click.
- Moves Endless real-hover polling to the addon's OnUpdate loop, where it can actually capture Endless Growth, Endless Might, and Endless Vitality while the skin is closed.
- NOT AVAILABLE nodes now show their cost in red as well as their state in red.
- Keeps affordable/unaffordable and prerequisite availability as separate states.
- Gives the server a slightly longer settle window before treating a native click as rejected.
- Uses 9 visible rows so the replacement fits the native Skill Tree frame cleanly when docked.

CleanTree v0.0.1-hotfix5

Hotfix5 changes:
- Fixes hotfix4's "invalid order function for sorting" crash with a deterministic strict comparator.
- Distinguishes prerequisite-locked nodes from nodes that are merely unaffordable.
- Locked/rejected nodes show red NOT AVAILABLE and keep the + button disabled.
- Unaffordable but otherwise learnable nodes still show AVAILABLE in red with a red cost and disabled + button.
- Checks disabled/desaturated controls inside the native node widget rather than trusting only an enabled wrapper.
- Captures Ebonhold's real "Left-click to learn" cue whenever a native skill-node tooltip is actually hovered.
- If Ebonhold rejects a click (no Soul Ash decrease), that node is immediately marked NOT AVAILABLE until prerequisites change or Refresh is used.
- Successful purchases clear cached negative availability because they may unlock dependent nodes.
- Endless placeholders remain built in for Endless Growth, Endless Vitality, and Endless Might.
- TODO for a later build: have /cleantree open /progression and select/load the Skill Tree tab automatically.

Hotfix4 changes:
- Fixes the pre-load /cleantree crash caused by setStatus being referenced before its local declaration.
- Removes Show Original and the floating CleanTree return button. Closing CleanTree now simply hides the skin.
- Keeps purchasable-but-unaffordable nodes visible, shows their cost/state in red, and disables the + button until enough Soul Ash is available.
- Adds all three known infinite nodes as permanent Endless-tab entries: Endless Growth, Endless Vitality, and Endless Might.
- Tries to bind Endless nodes from native widget names/metadata in addition to spell IDs.
- Adds a safe real-hover fallback: hovering an Endless node in the native tree captures its live rank, effect, cost, and clickable widget.
- Prevents Endless purchases until an authoritative live cost has been captured.
- /cleantree now fails gracefully with an instruction if Ebonhold's /progression -> Skill Tree tab has not been initialized yet.

CleanTree v0.0.1-hotfix3

Hotfix3 changes:
- Reads finite-node effects from the known spell IDs when native synthetic hover is unavailable.
- Searches node child widgets for native OnEnter tooltips instead of assuming metadata and tooltip scripts share one frame.
- Uses positive spell-known evidence plus validated rank text to determine ownership.
- Hides fully purchased finite nodes from the actionable list.
- Keeps Endless nodes visible and adds runtime Endless discovery from live spell metadata.
- Clears stale native bindings during Refresh so scrolling cannot resurrect stale availability state.

CleanTree v0.0.1-hotfix2
================
Project Ebonhold / WoW 3.3.5a

HOTFIX2
-------
- Fixes a 3.3.5 client error where discovery asked ordinary Frames for an
  unsupported OnClick script (for example skillTreeCanvas:GetScript("OnClick")).
- All native script probing is now protected and unsupported script types are
  treated as absent instead of throwing.
- Understands the /progression -> Skill Tree lazy-load lifecycle and waits while
  the native tab reports "Skill Tree loading..." before attempting to bind nodes.
- Adds bounded automatic retries when the native tree exists but has not populated
  its node buttons yet.

PURPOSE
-------
CleanTree is a replacement UI / skin for Project Ebonhold's Soul Ash Skill Tree.
It does NOT reimplement the server-side tree. The original Ebonhold tree stays
loaded underneath it and remains authoritative.

v0.0.1 SCOPE
------------
- Modern list-based replacement UI over the native tree.
- Tabs for Damage, Survival, Convenience, Endless, and All.
- Search by node name or live tooltip effect text.
- Live node effect, rank, cost, availability, and Carry over Prestige display.
- Stages one rank by clicking Ebonhold's original live node button.
- Tracks the actual Soul Ash decrease after each staged click.
- Pending Changes summarizes EFFECTS/PERKS, not just node names.
- Finds and clicks Ebonhold's native Apply Changes button.
- Watches ProjectEbonhold.SkillTree.OnApplyChangesResult when available.
- Includes the three Endless nodes by runtime discovery. AshBuild intentionally
  excludes them; CleanTree intentionally does not.
- Endless cost is always taken from the live tooltip when available, so the
  100,000,000 Soul Ash cost at rank 50+ is not hard-coded or hidden.
- Closing CleanTree hides the skin and leaves Ebonhold's native tree underneath when that tab is open.
- "Discard (/reload)" uses UI reload because Ebonhold owns staged state.

DATA
----
The finite-tree catalog is generated from AshBuild v1.0.0-beta3:
- 813 finite node IDs
- 937 finite rank/spell entries
- Damage / Survival / Convenience branch membership

CleanTree supplements that catalog by inspecting the live tree at runtime. This
is how it discovers Endless nodes and reads authoritative tooltip text/costs.

TOOLTIP / EFFECT HANDLING
-------------------------
The live Ebonhold tooltip is treated as authoritative.

Examples CleanTree can normalize:
    Increases Stamina by 5.
        -> +5 Stamina

    Increases your mana by 5%.
        -> +5% Mana

    You are immune to Daze effects.
        -> Immune to Daze effects

    Increases experience gained from gathering and killing monsters by an
    additional 40%.
        -> +40% experience from gathering and killing monsters

Conditional / unusual perks are intentionally kept as descriptive perk text
instead of being misrepresented as a flat stat gain.

INSTALL
-------
Copy the CleanTree folder to:
    <WoW>\Interface\AddOns\CleanTree

Then /reload.

USAGE
-----
Open Ebonhold's Skill Tree. CleanTree auto-opens by default.

Commands:
    /cleantree
    /cleantree show
    /cleantree native
    /cleantree refresh
    /cleantree probe
    /cleantree auto
    /cleantree apply

/cleantree probe is useful during v0.0.x testing. It reports:
- number of catalog/runtime nodes
- number of bound live buttons
- number of effects read
- Endless nodes found, ranks and live costs
- whether the native Apply Changes button was found

FIRST TEST REQUEST
------------------
1. Open the Skill Tree.
2. Confirm CleanTree opens.
3. Run /cleantree probe and save the chat output.
4. Check the Endless tab. Confirm Endless Vitality / Might / Growth appear.
5. Click a cheap AVAILABLE node through CleanTree.
6. Confirm Soul Ash drops and Pending Changes describes the perk/effect.
7. Use APPLY CHANGES only after visually confirming the staged purchase.
8. If anything is wrong, close CleanTree or /reload before applying.

Known v0.0.1 limitation:
The UI does not yet reproduce prerequisite connector topology. Availability is
borrowed from Ebonhold's native live button state. That is deliberate for the
first build: Ebonhold remains the source of truth while we validate the new UI.


v0.0.1-hotfix2
-----------------
- Replaced the synchronous 813 x live-frame node scan with an incremental binder.
- Added tooltip-based fallback binding when Ebonhold does not expose node/spell IDs.
- Follows ScrollFrame scroll children during native-tree discovery.
- /cleantree probe is now diagnostic/non-blocking and reports root/frame/discovery counts.
- Slash commands explicitly clear and dismiss the chat edit box on custom clients.
- Opening /cleantree no longer launches repeated full-tree searches from visible rows.


v0.0.1-hotfix6
- Hides native Skill Tree visuals while CleanTree is open; closing CleanTree restores them.
- Main window is draggable by the header.
- Removes over-aggressive disabled-child test that disabled every + button.
- Adds milestone prerequisite heuristic using earlier same-chain nodes.
- Lazily resolves visible unbound finite nodes against the native tree.
- Retries prematurely incomplete native binding scans.
- Polls native GameTooltip while CleanTree is hidden so hovering Endless nodes can bind them.
- Probe now dumps unmatched native candidates when Endless nodes remain unbound.