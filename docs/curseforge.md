<!--
CurseForge project page text. Paste the Summary into the project's Summary
field and everything under "Description" into the Description editor
(switch it to Markdown first). Not shipped in the addon zip (.pkgmeta
ignores docs/).

Logo: upload docs/images/logo.png (400x400). It's the 64px
Ability_Warrior_RallyingCry game icon, upscaled 4x with Real-ESRGAN
(realesrgan-x4plus), its gray game border cropped off, in a gold frame.

Images point at raw GitHub URLs, so they only load while the repo is
public. Otherwise upload them under the project's Images tab and swap the
links.
-->

# Summary

Call your guild for backup in WoW: Forever. One click tells guildmates you're being ganked, where the world PvP is, or that you're hunting a ganker, with a shared ganker list, KOS guilds, and bounties.

# Description

**Call your guild for backup in WoW: Forever.** One button tells every guildmate running Rallying Cry where you are and what's going on: you're being ganked, there's a world PvP fight worth joining, or you're putting a party together to hunt a ganker down.

Alerts go over the hidden guild addon channel. Nobody outside your guild sees them.

![Rallying Cry button panel](https://raw.githubusercontent.com/DigitalPenguin1/RallyingCry/main/docs/images/panel.png)

> **WoW: Forever only.** Built for the Forever client. It won't load on Classic Era and isn't supported on Retail. Your guildmates need Rallying Cry too.

## Alerts

- **Ganked!** sends your zone, subzone, and coordinates, plus your enemy target's name and guild
- **World PvP** points the guild at a fight worth joining
- **Hunt Ganker** rounds up a party to go after a ganker, by target or by name
- **All Clear** calls it off and removes the waypoint guildmates set to you

Guildmates get a banner, a sound, and an **Accept / Decline** window. Accept sets a waypoint to you and gets them invited to your group. A full party turns into a raid if you lead it.

## Shared ganker list

![Ganker List](https://raw.githubusercontent.com/DigitalPenguin1/RallyingCry/main/docs/images/ganker-list.png)

- Anyone named in a Ganked! or Hunt alert is added to the guild's list automatically, or add them by hand
- **Reports** and **Last seen**: see how often a ganker has been called out, and when and where a guildmate last ran into them
- **Warnings** when you target or mouse over a listed ganker
- **Bounties**: pledge gold on a ganker. The hunter claims it, the poster confirms and mails the gold, and paid bounties stay on record
- **KOS guilds**: officers can put a whole guild on KOS, including its numbered spin-offs (Olympus 2, Olympus II) or every guild starting with a name

![KOS guilds](https://raw.githubusercontent.com/DigitalPenguin1/RallyingCry/main/docs/images/kos-guilds.png)

## Syncs itself

There's no server and no account. The list lives on every guildmate's computer and stays in step over the guild channel. Changes go out in a second or two, and you catch up on anything you missed when you log in. Each guild has its own list, so an alt in another guild never sees or sends your main guild's list. Officers can export a backup and restore it.

## Getting around

- **Minimap button**: left-click for the panel, Shift-click for the ganker list, right-click for settings
- **Keybindings** for every alert, the panel, the ganker list, and the last alert's waypoint
- **Settings** under ESC > Options > AddOns > Rallying Cry, with a Sync page that shows who sent you what
- `/rc` lists every slash command, handy for macros

![Settings](https://raw.githubusercontent.com/DigitalPenguin1/RallyingCry/main/docs/images/settings.png)

## Limits

Forever uses the modern addon API, so some things are out of an addon's reach:

- No automatic gank detection. The combat log is blocked for addons, so you press the button
- The game can hide your target's name in combat. Use `/rc hunt First Surname` to name the ganker yourself
- No coordinates inside instances. The alert still sends the zone

## Feedback

Rallying Cry is new, so expect rough edges. Report bugs and ideas on [GitHub](https://github.com/DigitalPenguin1/RallyingCry/issues). If you enjoy it, you can [buy me a coffee](https://buymeacoffee.com/relyk22).
