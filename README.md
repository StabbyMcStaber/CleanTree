# 🌳 CleanTree

A cleaner way to use Project Ebonhold's Soul Ash Skill Tree.

Project Ebonhold's Skill Tree is enormous. CleanTree keeps the real Ebonhold tree and server logic underneath, but replaces the giant graph with a compact list/detail interface built directly into the native Progression window. Browse what is available, search by node or effect, stage purchases, review the cart, and apply changes without hunting through hundreds of icons.

---

## Table of Contents

- [🔥 Why this addon](#-why-this-addon)
- [✨ Features](#-features)
- [📋 Requirements](#-requirements)
- [💾 Installation](#-installation)
- [🚀 Quick start](#-quick-start)
- [🧭 Views](#-views)
- [🛒 Purchasing and cart](#-purchasing-and-cart)
- [♾️ Endless nodes](#️-endless-nodes)
- [↔️ Native Skill Tree coexistence](#️-native-skill-tree-coexistence)
- [⌨️ Commands](#️-commands)
- [🧱 Code anatomy](#-code-anatomy)
- [📜 License](#-license)
- [🙏 Credits](#-credits)

---

## 🔥 Why this addon

The native Ebonhold Soul Ash Skill Tree contains hundreds of nodes spread across a very large visual graph. Finding a specific effect, understanding what is currently unlockable, and reviewing staged purchases can take more time than the purchase itself.

CleanTree presents the same live tree as a stable, searchable list while leaving Project Ebonhold's actual purchase and Apply Changes behavior authoritative.

## ✨ Features

| | |
|---|---|
| 🧭 | Browse **All**, **Unowned**, **Damage**, **Survival**, **Convenience**, **Endless**, **Cart**, and **Purchased** views |
| 🔎 | Search nodes by name and discovered effect text |
| 🔗 | Order finite nodes by the real prerequisite graph so a node never appears before its prerequisites |
| 🚦 | Distinguish prerequisite-locked nodes from nodes that are merely unaffordable |
| 💰 | Show live Soul Ash state and stage purchases through Ebonhold's native Skill Tree |
| 🛒 | Review staged changes in a cart and remove staged ranks through the native right-click path |
| ✅ | Apply through Project Ebonhold's native **Apply Changes** operation |
| 🧾 | Distinguish server-committed purchases from changes staged only in the current tree |
| ♾️ | Include all three Endless nodes as repeatable multi-rank purchases |
| ↔️ | Switch between **CleanTree** and the original Ebonhold Skill Tree at any time |
| 🧪 | Keep diagnostic commands available for EbonAPI/native-tree troubleshooting |

## 📋 Requirements

| | |
|---|---|
| Game | World of Warcraft 3.3.5a on Project Ebonhold |
| Integration | ProjectEbonhold, included with the Ebonhold client |
| Required addon | [EbonAPI](https://github.com/Siphelis/EbonAPI) 1.0+ — installed separately; CleanTree does not bundle it |

`SkillTreeAutoLoad` is **not** required. CleanTree and SkillTreeAutoLoad can coexist because both consume the shared EbonAPI integration layer independently.

## 💾 Installation

1. Download the latest `CleanTree-vX.Y.Z.zip` from the [Releases page](https://github.com/StabbyMcStaber/CleanTree/releases/latest).
2. Install [EbonAPI](https://github.com/Siphelis/EbonAPI/releases/latest) if it is not already installed.
3. Extract the `CleanTree` folder into your Ebonhold client's `Interface/AddOns/` folder.
4. Restart the game and make sure **EbonAPI** and **CleanTree** are enabled in the AddOns list.
5. Open **Progression → Skill Tree** normally. CleanTree replaces the Skill Tree content area automatically.

> CleanTree does not create a separate floating replacement window. It lives inside the native Progression shell.

## 🚀 Quick start

1. Open **Progression → Skill Tree**.
2. Use **Unowned** for the normal working view, or choose a branch tab.
3. Select a node to inspect its rank, effect, cost, prerequisite state, and purchase state.
4. Press `+` to stage one rank through the native Ebonhold Skill Tree.
5. Review staged changes in **Cart**.
6. Click **Apply Changes** when you are ready to commit the staged tree to the server.

Availability and affordability are intentionally separate:

- **NOT AVAILABLE** means the real prerequisite requirements are not satisfied.
- **AVAILABLE** with insufficient Soul Ash means the prerequisites are satisfied, but the rank cannot currently be afforded.
- **AVAILABLE** and affordable means the rank can be staged.

## 🧭 Views

| View | Purpose |
|---|---|
| **All** | Every discovered node, including purchased nodes |
| **Unowned** | The normal working list of unfinished finite nodes |
| **Damage** | Unfinished nodes under Rising Carnage |
| **Survival** | Unfinished nodes under Essence of Endurance |
| **Convenience** | Unfinished nodes under Unshaken |
| **Endless** | Endless Vitality, Endless Might, and Endless Growth |
| **Cart** | Ranks staged in the native tree but not yet committed |
| **Purchased** | Server-committed ranks reported by EbonAPI |

List order is stable. CleanTree does not move a node around merely because it becomes affordable or available; state and button styling communicate what can be done now.

## 🛒 Purchasing and cart

CleanTree is a replacement presentation layer, not a separate Skill Tree simulator.

A `+` click stages the corresponding live native node. Cart removal uses the native tree's staged-removal behavior when available. **Apply Changes** invokes Project Ebonhold's native apply path, so the server remains authoritative for the final result.

`Discard (/reload)` remains available as a safe fallback for abandoning staged changes when a reliable native full-reset path is not available.

## ♾️ Endless nodes

CleanTree intentionally includes the three infinite nodes:

- `2000` — Endless Vitality
- `2001` — Endless Might
- `2002` — Endless Growth

Endless nodes are not treated as ordinary 0/1 nodes. Each `+` click stages one additional rank, the current rank is read from the live native tree state, and the next cost is calculated from EbonAPI's Talent Database data with the live high-rank cost behavior respected.

## ↔️ Native Skill Tree coexistence

CleanTree deliberately keeps an escape hatch to the stock Ebonhold interface:

- In CleanTree, click **Restore Native Skill Tree**.
- In native mode, click **Restore CleanTree UI** to switch back.

Your current choice is preserved while moving between Progression tabs and reopening the Skill Tree.

## ⌨️ Commands

CleanTree normally opens by using the Skill Tree naturally through the Progression window. `/cleantree` by itself is not intended as a standalone launcher.

Useful commands include:

```text
/cleantree show
/cleantree native
/cleantree refresh
/cleantree probe
/cleantree orderprobe
/cleantree graphprobe <node name>
/cleantree apiprobe
/cleantree auto
/cleantree apply
```

Diagnostic commands are intentionally retained so Ebonhold/EbonAPI changes can be investigated without requiring a special debug build.

## 🧱 Code anatomy

```text
CleanTree/
├── CleanTree.toc       addon metadata, dependencies, load order
├── EbonTree_Data.lua   captured finite-tree fallback/catalog data
├── EbonTree_Order.lua  stable prerequisite ordering snapshot
├── EbonTree_API.lua    EbonAPI integration layer
├── EbonTree.lua        UI, native-tree binding, purchasing, cart, diagnostics
└── README.txt          in-addon release/development notes
```

Some internal filenames and symbols still use the project's earlier `EbonTree` name. That is intentional and does not change the installed addon folder/name: **CleanTree**.

## 📜 License

CleanTree is free for noncommercial use and is published under the [PolyForm Strict License 1.0.0](LICENSE.md). You may use the addon for permitted noncommercial purposes, but modification and redistribution are restricted by that license.

## 🙏 Credits

Addon by **Stan**, built with **CarolJean**.

Built for [Project Ebonhold](https://project-ebonhold.com/) and designed around the shared [EbonAPI](https://github.com/Siphelis/EbonAPI) integration layer.

[SkillTreeAutoLoad](https://github.com/Siphelis/SkillTreeAutoLoad) was used as a reference for EbonAPI consumption and native Skill Tree integration. It is not a CleanTree dependency and no SkillTreeAutoLoad source is bundled with CleanTree.
