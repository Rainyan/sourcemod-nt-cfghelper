/*
	Phrase reading from .ini file borrowed from
	"Bad name ban" by vIr-Dan and Lebson506th as per the SourceMod licence.
	https://forums.alliedmods.net/showthread.php?p=498974?p=498974
	http://www.sourcemod.net/license.php
*/

#pragma semicolon 1

#include <sourcemod>
#include <basecomm>

#define PLUGIN_VERSION "1.5.2"

#define PHRASES_MAX_AMOUNT 32
#define PHRASES_MAX_LENGTH 32

enum {
	NONE = 0,
	YES,
	NO
};

new g_lines;
new g_chatSpamDetections[MAXPLAYERS+1];
new g_rebindPreference[MAXPLAYERS+1];

new String:g_fileName[PLATFORM_MAX_PATH];
new String:g_phrases[PHRASES_MAX_AMOUNT][PHRASES_MAX_LENGTH];

public Plugin:myinfo =
{
	name = "NT Malicious CFG Helper",
	author = "Rain",
	description = "Help players whose config appears maliciously overwritten",
	version = PLUGIN_VERSION,
	url = ""
};

public OnPluginStart()
{
	AddCommandListener(SayCallback, "say");
	AddCommandListener(SayCallback, "say_team");

	HookEvent("player_activate", Event_NameCheck, EventHookMode_Pre);
	HookEvent("player_changename", Event_NameCheck, EventHookMode_Pre);

	RegConsoleCmd("sm_stop", Command_CancelRebind);
	RegConsoleCmd("sm_fixmyconfig", Command_FixMyConfig);

	RegAdminCmd("sm_cfghelper_reload", Command_ReloadPhrases, ADMFLAG_KICK, "Reload CFG Helper filter phrases");
	RegAdminCmd("sm_fixconfig", Command_FixConfig, ADMFLAG_KICK, "Admin command to suggest rebinding to default");
}

public OnMapStart()
{
	ReadConfig();
}

public OnClientDisconnect(client)
{
	g_chatSpamDetections[client] = 0;
	g_rebindPreference[client] = NONE;
}

public Action:Command_CancelRebind(client, args)
{
	switch (g_rebindPreference[client])
	{
		case YES:
		{
			g_rebindPreference[client] = NO;
			PrintToChat(client, "[SM] Ok, won't rebind your keys to default.");
		}

		case NO:
		{
			g_rebindPreference[client] = YES;
			PrintToChat(client, "[SM] Ok, will rebind your keys to default.");
		}

		// Ignore command if not relevant to player
		case NONE:
		{
			return Plugin_Stop;
		}
	}

	return Plugin_Handled;
}

public Action:Command_FixConfig(client, args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: !fixconfig \"playername\"");
		return Plugin_Handled;
	}

	new String:arg1[MAX_NAME_LENGTH];
	GetCmdArg(1, arg1, sizeof(arg1));

	new target = FindTarget(client, arg1);

	if (target == -1)
		return Plugin_Handled;

	OfferRebind(target);

	decl String:targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, sizeof(targetName));

	ReplyToCommand(client, "[SM] Offered rebinding to \"%s\"", targetName);

	return Plugin_Handled;
}

public Action:Command_FixMyConfig(client, args)
{
	OfferRebind(client);
	return Plugin_Handled;
}

public Action:Command_ReloadPhrases(client, args)
{
	ReadConfig();
	ReplyToCommand(client, "[SM] CFG Helper filter phrases reloaded");
	return Plugin_Handled;
}

public Action:Event_NameCheck(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);

	decl String:clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));

	if (HasMaliciousCfg(clientName))
	{
		ClientCommand(client, "name NeotokyoNoob");
		PrintToChat(client, "[SM] You were renamed to \"NeotokyoNoob\".");
		PrintToChat(client, "Your name was previously set to: \"%s\"", clientName);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action:Timer_Rebind(Handle:timer, any:client)
{
	if (g_rebindPreference[client] == YES)
	{
		g_rebindPreference[client] = NONE;
		ClientCommand(client, "exec config_default");
		ClientCommand(client, "host_writeconfig");
		PrintToConsole(client, "**********");
		PrintToConsole(client, "[SM] All your keys have been rebound back to defaults.");
		PrintToConsole(client, "**********");
	}

	else
	{
		PrintToChat(client, "[SM] No rebinding done as requested.");
		PrintToChat(client, "However, you will be gagged until the next map.");
	}

	g_rebindPreference[client] = NONE;
}

public Action:SayCallback(client, const String:command[], argc)
{
	if (!client) // Message sent by server, don't bother checking
		return Plugin_Continue;

	new String:message[256];
	GetCmdArgString(message, sizeof(message));

	if (HasMaliciousCfg(message))
	{
		g_chatSpamDetections[client]++;
		if (g_chatSpamDetections[client] >= 3)
		{
			BaseComm_SetClientGag(client, true);

			decl String:clientName[256];
			GetClientName(client, clientName, sizeof(clientName));

			PrintToAdmins("To admins: %s triggered hacked cfg detection by typing:", clientName);
			PrintToAdmins("\"%s\"", message);
			PrintToAdmins("Blocked message, gagged, and instructed player on fixing configs.", " ");

			LogToGame("[SM] Gagged %s for triggering the hacked cfg detection. Chat message spammed was: \"%s\".", clientName, message);

			PrintToChat(client, "[SM] You have been gagged for typing this message:");
			PrintToChat(client, "\"%s\"", message);
			PrintToChat(client, "- - - - - - - - - -", " ");
			PrintToChat(client, "It looks like a malicious server may have overwritten your configs.");
			PrintToChat(client, "- - - - - - - - - -", " ");

			OfferRebind(client);
		} else {
			PrintToChat(client, "[SM] Your chat message has been blocked for triggering a spam filter.");
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void PrintToAdmins(const String:message[], any ...)
{
	decl String:formatMsg[512];
	VFormat(formatMsg, sizeof(formatMsg), message, 2);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsValidAdmin(i))
			continue;

		PrintToChat(i, formatMsg);
		PrintToConsole(i, formatMsg);
	}
}

bool IsValidAdmin(client)
{
	if ((CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK)) && (IsClientConnected(client)) && (!IsFakeClient(client)))
		return true;

	return false;
}

bool HasMaliciousCfg(const String:sample[])
{
	//PrintToServer("Test Sample: %s", sample);

	decl String:cleanedMessage[strlen(sample) + 1];
	new pos_cleanedMessage;

	// Trim all non-alphanumeric characters
	for (new i = 0; i < strlen(sample); i++)
	{
		//PrintToServer("Strlen: %i", strlen(sample));

		if (IsCharAlpha(sample[i]) || IsCharNumeric(sample[i]))
		{
			//PrintToServer("True, copying over character %c", sample[i]);
			cleanedMessage[pos_cleanedMessage] = sample[i];
			pos_cleanedMessage++;
		}
	}
	cleanedMessage[pos_cleanedMessage] = 0; // string terminator

	//PrintToServer("Cleaned Sample: %s", cleanedMessage);

	for (new i = 0; i < g_lines; i++)
	{
		if (StrContains(cleanedMessage, g_phrases[i], false) != -1)
		{
			//PrintToServer("Cleaned msg %s contains phrase %s", cleanedMessage, g_phrases[i]);
			return true;
		}
	}

	return false;
}

void ReadConfig()
{
	// Clear old phrases
	for(new i; i < g_lines; i++)
	{
		g_phrases[i] = "";
	}
	g_lines = 0;

	// Build path to phrases config
	BuildPath(Path_SM, g_fileName, sizeof(g_fileName), "configs/nt_cfghelper_phrases.ini");
	new Handle:file = OpenFile(g_fileName, "r");

	if (file == INVALID_HANDLE)
		ThrowError("Couldn't read from %s", g_fileName);

	decl String:line[64];
	while (!IsEndOfFile(file))
	{
		if (!ReadFileLine(file, line, sizeof(line)))
			break;

		TrimString(line);

		if (strlen(line) == 0 || (line[0] == '/' && line[1] == '/'))
			continue;

		strcopy(g_phrases[g_lines], sizeof(g_phrases[]), line);
		g_lines++;
	}

	CloseHandle(file);
}

void OfferRebind(client)
{
	g_rebindPreference[client] = YES;
	PrintToChat(client, "Going to automatically rebind keys to default in 10 seconds...");
	PrintToChat(client, "Type !stop to cancel.");
	CreateTimer(10.0, Timer_Rebind, client);
}
