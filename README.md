sourcemod-nt-cfghelper
======================

This plugin was created to counter certain trolls creating malicious SRCDS servers that would change the connected players' binds to spam stuff (slowhacking).<br />

It uses a filter to detect affected players, and automatically suggests/rebinds their keyboard layout back to
game defaults.<br />

Created for Neotokyo, but should work for any Source SDK 2006 game. Newer Source games generally block the <i>ClientCommand</i> used here (which probably means you wouldn't need this plugin anyway).
