# Changelog

## Unreleased

- Guilds list: the Added by name no longer gets cut off
- Panel order: Ganker List sits above All Clear, which is now at the bottom
- KOS guild families: adding Olympus also covers Olympus 2, Olympus II, and so on, and Olympus* covers every guild starting with Olympus. Add Guild fills in the base name when you target a numbered guild
- Hunt Ganker is blue instead of purple
- Slash commands that take a name (`/rc hunt`, `/rc kos add`, `/rc bounty`) read the full first name and surname
- KOS guilds no longer save the shard name the game reports as a realm, since Forever has no realms
- Fix: Forever surnames. Players are now identified by first name + surname like the game does, instead of mistaking the surname for a realm. This fixes the GM not being recognized as an officer, your own alerts popping up for you, and enemy names saved as "Name-Surname"

## 0.4.0

- KOS guilds: officers can put a whole guild on KOS. Every member counts as a ganker, and you're warned when you target or mouse over one
- The ganker list window has a Gankers | Guilds toggle, and Add Guild can fill in your target's guild
- Alerts and ganker entries show the ganker's guild, marked if it's a KOS guild
- Officers are now ranks with the guild's Remove Member permission, instead of rank 0 and 1
- Long alert notes are trimmed to fit WoW's message limit instead of failing to send, without cutting accented letters in half

- Add Ganker is now a form with separate Name, Reason, and Bounty fields, plus a Use Target button
- The alert banner shows below the Accept/Decline window instead of behind it, and fades out after a few seconds
- All Clear only sends while you have an alert out (10 minutes), so it can't be spammed
- All Clear removes the waypoint guildmates set to your alert, unless they've moved it themselves
- `/rc go` and the waypoint keybind no longer go to an alert that was called off
- Removed the All Clear checkbox from settings, which had nothing to turn off

## 0.3.0

- Guild ganker list: shared with every guildmate running Rallying Cry, and caught up automatically when you log in
- Gankers named in your Ganked! and Hunt alerts are added for you, with a report count and where they were last seen
- Bounties: pledge gold on a ganker. The hunter claims it, the poster confirms the kill and mails the gold
- Warning and sound when you target or mouse over a listed ganker
- Only the person who added a ganker, or an officer (guild rank 0 or 1), can remove them
- Open the list from the panel, Shift-click the minimap button, a keybinding, or `/rc kos`
- About page in settings (ESC > Options > AddOns > Rallying Cry > About) with version, author, and copyable support and GitHub links
- Minimap button (on by default): left-click toggles the panel, right-click opens settings, drag to move, tooltip shows the last alert. Turn it off in settings or with `/rc minimap`
- Settings page under ESC > Options > AddOns > Rallying Cry. Open it with the gear on the panel, `/rc settings`, or right-click the addon compartment entry
- Forever gold and bronze theme for the panel, buttons, chat tag, and addon list title (was red)

## 0.2.0

- Incoming alerts pop up an Accept/Decline window
- Accept sets a waypoint and the alerter auto-invites you, turning a full party into a raid if they lead it
- The alerter sees who's on the way. Responders get told when an invite can't happen and why
- New toggles: `/rc popup`, `/rc invite`, `/rc raid`

## 0.1.0

First version.

- Four guild alerts: Ganked!, World PvP, Hunt Ganker, All Clear
- Alerts carry zone, subzone, coordinates, your enemy target's name, and an optional note
- Chat line, raid-warning banner, and sound on incoming alerts
- Draggable button panel, keybindings, and an Addon Compartment entry
- `/rc go` and optional auto-waypoint to the alert location
- Saved alert log, per-type mute, and a send cooldown
