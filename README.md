# Rallying Cry

Call your guild for backup in **WoW: Forever**. One button tells every guildmate running Rallying Cry where you are and what's going on: you're being ganked, there's a world PvP fight worth joining, or you're putting together a party to hunt a ganker down.

Alerts go over the hidden guild addon channel. Nobody outside your guild sees them, and you have to be in a guild to send or receive.

> **WoW: Forever only.** Built for the Forever client (interface 16001). It won't load on Classic Era, and isn't supported on Retail.

## Alerts

| Alert | Command | What guildmates see |
|---|---|---|
| **Ganked!** | `/rc gank [note]` | You're being ganked, plus your zone, subzone, and coordinates |
| **World PvP** | `/rc wpvp [note]` | There's a fight at your location |
| **Hunt Ganker** | `/rc hunt [name] [note]` | You're hunting a ganker. Uses your target if it's an enemy player, otherwise the name you type |
| **All Clear** | `/rc clear` | You're safe, call it off |

Each incoming alert shows up in chat and as a raid-warning banner, with a sound. If your target is an enemy player when you send, their name rides along.

## Accept or Decline

Ganked!, World PvP, and Hunt Ganker alerts pop up a window for guildmates with **Accept** and **Decline**.

- **Accept** puts a waypoint on the alert and tells the person who sent it. Their client invites you automatically, so they don't have to stop fighting to do it. If their party is full and they lead it, it turns into a raid first.
- **Decline** closes the window. Nothing gets sent.

The window closes on its own after 60 seconds, or when the sender calls All Clear. If you're already in a group you can't be invited, but the sender still hears you're on the way. If they can't invite you (they aren't group leader, or the raid is full), you get told why and can follow the waypoint.

## Ganker List and Bounties

The guild keeps one shared list of gankers. Anyone running Rallying Cry sees the same list, and it catches you up on anything you missed when you log in.

- **Adding**: anyone named in your Ganked! or Hunt alert goes on the list automatically, and repeat reports bump their count and last-seen zone. You can also click **Add Ganker** or type `/rc kos add Name reason`
- **Removing**: only the person who added them, or an officer, can take someone off. Officers are guild rank 0 (Guild Master) and 1
- **Bounties**: click **Bounty** on a row, or `/rc bounty Name 50`, to pledge 50 gold. Several guildmates can stack bounties on the same ganker. `/rc bounty Name 0` withdraws yours
- **Claiming**: kill a ganker with a bounty, then click **Claim** or type `/rc claim Name`. Each poster gets a Confirm/Deny window (even if they were offline when you claimed). Confirm reminds them to mail you the gold
- **Warnings**: target or mouse over a listed ganker and you get a chat warning and a sound, with their bounty

The addon can't hold or move gold. A bounty is a pledge, and the poster pays it by mail.

## Features

- **Settings page**: ESC > Options > AddOns > Rallying Cry, the gear on the panel, `/rc settings`, or right-click Rallying Cry in the addon compartment. Every option below is there as a checkbox
- **Minimap button**: left-click toggles the panel, right-click opens settings, drag to move. Hover to see the last alert. On by default, turn it off in settings or with `/rc minimap`
- **Button panel**: draggable, one click per alert. Works in combat. `/rc panel` to show or hide
- **Keybindings**: ESC > Options > Keybindings > AddOns > Rallying Cry
- **Waypoints**: `/rc go` pins the last alert on your map and tracks it. `/rc waypoint` does it automatically for every alert
- **Alert log**: `/rc log` shows the last 10 alerts, saved across sessions
- **Mute by type**: `/rc mute wpvp` keeps an alert type in chat but drops the banner and sound
- **Spam guard**: 10 second cooldown between your alerts (All Clear is exempt), and repeat alerts from the same person get dropped

## All commands

```
/rc gank [note]         you're being ganked
/rc wpvp [note]         world PvP here
/rc hunt [name] [note]  hunting a ganker
/rc clear               call off your alert
/rc go                  waypoint to the last alert
/rc log                 recent alerts
/rc kos                 open the ganker list
/rc kos add <name> [reason]
/rc kos remove <name>
/rc bounty <name> <gold> pledge gold on a ganker (0 withdraws)
/rc claim <name>        claim the bounties on a ganker you killed
/rc settings            open the settings page
/rc panel               show/hide the button panel
/rc minimap             show/hide the minimap button
/rc sound               toggle alert sound
/rc banner              toggle the screen banner
/rc waypoint            toggle auto-waypoint
/rc popup               toggle the Accept/Decline window
/rc invite              toggle auto-inviting guildmates who accept
/rc raid                toggle turning a full party into a raid
/rc mute <type>         silence gank, wpvp, hunt, or clear
/rc version             addon and protocol version
/rc debug               debug output
```

## Limits

Forever runs the modern addon API with Midnight's restrictions, which shapes what Rallying Cry can do:

- **No automatic gank detection.** The combat log is blocked for addons, so you press the button yourself.
- **Target names can be hidden in combat.** If the game hides your target's name, the alert goes out without it. Use `/rc hunt Name` to name the ganker by hand.
- **No coordinates inside instances.** The game hides your position there. The alert still sends the zone name.
- **Ganker warnings may not fire in combat**, for the same reason.
- Guildmates only see alerts if they have Rallying Cry installed.

## Install

Unzip into `World of Warcraft/_classic_beta_/Interface/AddOns/` so you get `AddOns/RallyingCry/RallyingCry.toc`, then restart the game.

## License

GPL-3.0. See [LICENSE](LICENSE).
