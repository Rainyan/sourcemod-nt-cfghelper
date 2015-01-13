/*
	Phrase reading from .ini file borrowed from
	"Bad name ban" by vIr-Dan and Lebson506th as per the SourceMod licence.
	http://www.sourcemod.net/license.php
	https://forums.alliedmods.net/showthread.php?p=498974?p=498974
*/

#pragma semicolon 1

#include <sourcemod>
#include <basecomm>

#define PLUGIN_VERSION "1.4"

#define PHRASES_MAX_AMOUNT 32
#define PHRASES_MAX_LENGTH 32

#define NONE 0
#define YES 1
#define NO 2

new chatSpamDetections[MAXPLAYERS+1];
new lines;
new wantsRebind[MAXPLAYERS+1];

new String:fileName[PLATFORM_MAX_PATH];
new String:phrases[PHRASES_MAX_AMOUNT][PHRASES_MAX_LENGTH];

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
	
	RegAdminCmd("sm_fixconfig", Command_FixConfig, ADMFLAG_KICK, "Admin command to suggest rebinding to default");
}

public OnConfigsExecuted()
{
	ReadConfig();
	RegAdminCmd("sm_cfghelper_reload", Command_ReloadPhrases, ADMFLAG_KICK, "Reload CFG Helper filter phrases");
}

public OnMapStart()
{
	for(new i; i < lines; i++)
		phrases[i] = "";
		
	lines = 0;
}

public OnClientDisconnect(client)
{
	chatSpamDetections[client] = 0;
	wantsRebind[client] = NONE;
}

public Action:Event_NameCheck(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	new String:clientName[256];
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

public Action:OfferRebind(client)
{
	wantsRebind[client] = YES;
	PrintToChat(client, "Going to automatically rebind keys to default in 10 seconds...");
	PrintToChat(client, "Type !stop to cancel.");
	CreateTimer(10.0, Timer_Rebind, client);
}

public Action:Timer_Rebind(Handle:timer, any:client)
{
	if (wantsRebind[client] == YES)
	{
		wantsRebind[client] = NONE;
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
	
	wantsRebind[client] = NONE;
}

public Action:Command_CancelRebind(client, args)
{
	// ignore cmd if not relevant to player
	if (wantsRebind[client] == NONE)
		return Plugin_Stop;
	
	else if (wantsRebind[client] == YES)
	{
		wantsRebind[client] = NO;
		PrintToChat(client, "[SM] Ok, won't rebind your keys to default.");
	}
	
	else
	{
		wantsRebind[client] = YES;
		PrintToChat(client, "[SM] Ok, will rebind your keys to default.");
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
	
	new String:targetName[MAX_NAME_LENGTH];
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

public Action:SayCallback(client, const String:command[], argc)
{
	if (!client) // Message sent by server, don't bother checking
		return Plugin_Continue;

	new String:message[256];
	GetCmdArgString(message, sizeof(message));
	
	new String:clientName[256];
	GetClientName(client, clientName, sizeof(clientName));
	
	if (HasMaliciousCfg(message))
	{
		chatSpamDetections[client]++;
		if (chatSpamDetections[client] >= 3)
		{
			BaseComm_SetClientGag(client, true);
			
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

stock PrintToAdmins(const String:message[256], const String:name[256])
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsValidAdmin(i))
		{
			PrintToChat(i, message, name);
			PrintToConsole(i, message, name);
		}
	}
}

bool:IsValidAdmin(client)
{
	if ((CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK)) && (IsClientConnected(client)) && (!IsFakeClient(client)))
		return true;

	return false;
}

bool:HasMaliciousCfg(String:sample[256])
{
	new String:cleanedMessage[sizeof(sample) + 1];
	new pos_cleanedMessage;
	
	// Trim all non-alphanumeric characters
	for (new i = 0; i < sizeof(sample); i++)
	{
		if (IsCharAlpha(sample[i]) || IsCharNumeric(sample[i]))
			cleanedMessage[pos_cleanedMessage++] = sample[i];
	}

	// Terminate the string with 0
	cleanedMessage[pos_cleanedMessage] = '\0';
	
	for (new i = 0; i < lines; i++)
	{
		if (StrContains(cleanedMessage, phrases[i], false) != -1)
			return true;
	}
	
	return false;
}

public Action:ReadConfig()
{
	BuildPath(Path_SM, fileName, sizeof(fileName), "configs/nt_cfghelper_phrases.ini");
	new Handle:file = OpenFile(fileName, "r");

	if (file == INVALID_HANDLE)
	{
		LogError("[nt cfg helper] Couldn't read from %s", fileName);
		SetFailState("Couldn't read from %s", fileName);
	}
	
	while (!IsEndOfFile(file))
	{
		decl String:line[64];

		if (!ReadFileLine(file, line, sizeof(line)))
			break;

		TrimString(line);

		if (strlen(line) == 0 || (line[0] == '/' && line[1] == '/'))
			continue;

		strcopy(phrases[lines], sizeof(phrases[]), line);
		lines++;
	}
	
	CloseHandle(file);
}