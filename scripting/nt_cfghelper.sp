/*
	Phrase reading from .ini file borrowed from
	"Bad name ban" by vIr-Dan and Lebson506th as per the SourceMod licence.
	http://www.sourcemod.net/license.php
	https://forums.alliedmods.net/showthread.php?p=498974?p=498974
*/

#pragma semicolon 1

#include <sourcemod>
#include <basecomm>

#define PLUGIN_VERSION "1.2"

#define NONE 2
#define YES 1
#define NO 0

new chatSpamDetections[MAXPLAYERS+1] = 0;
new wantsRebind[MAXPLAYERS+1] = NONE;
new String:fileName[PLATFORM_MAX_PATH];
new String:phrases[256][64];

new lines;

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
}

public OnConfigsExecuted()
{
	ReadConfig();
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
		ClientCommand(client, "name %s", "NeotokyoNoob");
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
		PrintToConsole(client, "**********");
		PrintToConsole(client, "[SM] Rebound all your keys back to default.");
		PrintToConsole(client, "[SM] Please restart the game to save changes.");
		PrintToConsole(client, "**********");
		CreateTimer(0.5, KickSoonAfter, client);
	}
	else
	{
		PrintToChat(client, "[SM] No rebinding done as requested. However, you will be gagged until the next map.");
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

public Action:Command_FixMyConfig(client, args)
{
	OfferRebind(client);
}

public Action:SayCallback(client, const String:command[], argc)
{
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

public Action:KickSoonAfter(Handle:timer, any:client)
{
	KickClient(client, "All keys were reset to default. Please restart the game to save these changes.");
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
	new pos_cleanedMessage = 0;
	
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