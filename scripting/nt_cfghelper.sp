/*
	Phrase reading from .ini file borrowed from
	"Bad name ban" by vIr-Dan and Lebson506th as per the GPLv3 licence.
	https://forums.alliedmods.net/showthread.php?p=498974?p=498974
	https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#pragma semicolon 1

#include <sourcemod>
#include <basecomm>

#define PLUGIN_VERSION "1.5.2"
//#define DEBUG

#define MAX_STEAMID_LENGTH 44
#define PHRASES_MAX_AMOUNT 32
#define PHRASES_MAX_LENGTH 32

enum {
	NONE = 0,
	YES,
	NO
};

int g_lines;
int g_chatSpamDetections[MAXPLAYERS+1];
int g_rebindPreference[MAXPLAYERS+1];

char g_fileName[PLATFORM_MAX_PATH];
char g_phrases[PHRASES_MAX_AMOUNT][PHRASES_MAX_LENGTH];

public Plugin myinfo =
{
	name = "NT Malicious CFG Helper",
	author = "Rain",
	description = "Help players whose config appears maliciously overwritten",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	AddCommandListener(SayCallback, "say");
	AddCommandListener(SayCallback, "say_team");

	HookEvent("player_activate", Event_NameCheck, EventHookMode_Pre);
	HookEvent("player_changename", Event_NameCheck, EventHookMode_Pre);

	RegConsoleCmd("sm_cfg_stop", Command_CancelRebind);
	RegConsoleCmd("sm_fixmyconfig", Command_FixMyConfig);

	RegAdminCmd("sm_cfghelper_reload", Command_ReloadPhrases, ADMFLAG_KICK, "Reload CFG Helper filter phrases");
	RegAdminCmd("sm_fixconfig", Command_FixConfig, ADMFLAG_KICK, "Admin command to suggest rebinding to default");

	ReadConfig();
}

public void OnClientDisconnect(int client)
{
	g_chatSpamDetections[client] = 0;
	g_rebindPreference[client] = NONE;
}

public Action Command_CancelRebind(int client, int args)
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

public Action Command_FixConfig(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: !fixconfig \"playername\"");
		return Plugin_Handled;
	}

	char arg1[MAX_NAME_LENGTH];
	GetCmdArg(1, arg1, sizeof(arg1));

	int target = FindTarget(client, arg1);

	if (target == -1)
		return Plugin_Handled;

	OfferRebind(target);

	decl String:targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, sizeof(targetName));

	ReplyToCommand(client, "[SM] Offered rebinding to \"%s\"", targetName);

	return Plugin_Handled;
}

public Action Command_FixMyConfig(int client, int args)
{
	OfferRebind(client);
	return Plugin_Handled;
}

public Action Command_ReloadPhrases(int client, int args)
{
	ReadConfig();
	ReplyToCommand(client, "[SM] CFG Helper filter phrases reloaded");
	return Plugin_Handled;
}

public Action Event_NameCheck(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

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

public Action Timer_Rebind(Handle timer, DataPack data)
{
	char steamid[MAX_STEAMID_LENGTH];
	data.Reset();
	data.ReadString(steamid, sizeof(steamid));

	int client = GetClientOfAuthId(steamid);
	if (!client)
		return Plugin_Stop;

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
		PrintToChat(client, "However, you will remain chat blocked until the next map.");
	}

	g_rebindPreference[client] = NONE;

	return Plugin_Handled;
}

public Action SayCallback(int client, const char[] command, int argc)
{
	if (!client) // Message sent by server, don't bother checking
		return Plugin_Continue;

	decl String:message[256];
	GetCmdArgString(message, sizeof(message));

	if (HasMaliciousCfg(message))
	{
		g_chatSpamDetections[client]++;
		if (g_chatSpamDetections[client] >= 3)
		{
			BaseComm_SetClientGag(client, true);

			decl String:clientName[MAX_NAME_LENGTH];
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

void PrintToAdmins(const char[] message, any ...)
{
	decl String:formatMsg[512];
	VFormat(formatMsg, sizeof(formatMsg), message, 2);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidAdmin(i))
			continue;

		PrintToChat(i, formatMsg);
		PrintToConsole(i, formatMsg);
	}
}

bool IsValidAdmin(int client)
{
	if ((CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK)) && (IsClientConnected(client)) && (!IsFakeClient(client)))
	{
		return true;
	}
	return false;
}

bool HasMaliciousCfg(const char[] sample)
{
#if defined DEBUG
	PrintToServer("Test Sample: %s", sample);
#endif

	int sampleLength = strlen(sample);
	if (sampleLength < 1)
		ThrowError("Message sample is %i length, expected at least 1.", sampleLength);

	decl String:cleanedMessage[sampleLength + 1];
	int pos_cleanedMessage;

	// Trim all non-alphanumeric characters
	for (int i = 0; i < sampleLength; i++)
	{
#if defined DEBUG
		PrintToServer("Strlen: %i", strlen(sample));
#endif
		if (IsCharAlpha(sample[i]) || IsCharNumeric(sample[i]))
		{
#if defined DEBUG
			PrintToServer("True, copying over character %c", sample[i]);
#endif
			cleanedMessage[pos_cleanedMessage] = sample[i];
			pos_cleanedMessage++;
		}
	}
	cleanedMessage[pos_cleanedMessage] = 0; // string terminator

#if defined DEBUG
	PrintToServer("Cleaned Sample: %s", cleanedMessage);
#endif

	for (int i = 0; i < g_lines; i++)
	{
		if (StrContains(cleanedMessage, g_phrases[i], false) != -1)
		{
#if defined DEBUG
			PrintToServer("Cleaned msg %s contains phrase %s", cleanedMessage, g_phrases[i]);
#endif
			return true;
		}
	}

	return false;
}

void ReadConfig()
{
	// Clear old phrases
	for(int i = 0; i < g_lines; i++)
	{
		g_phrases[i] = "";
	}
	g_lines = 0;

	// Build path to phrases config
	BuildPath(Path_SM, g_fileName, sizeof(g_fileName), "configs/nt_cfghelper_phrases.ini");
	Handle file = OpenFile(g_fileName, "r");

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

void OfferRebind(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client) || !IsClientAuthorized(client))
		return;

	g_rebindPreference[client] = YES;
	PrintToChat(client, "Going to automatically rebind keys to default in 10 seconds...");
	PrintToChat(client, "Type !cfg_stop to cancel.");

	char steamid[MAX_STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));

	DataPack data = new DataPack();
	data.WriteString(steamid);

	CreateDataTimer(10.0, Timer_Rebind, data);
}

bool IsValidClient(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;

	return true;
}

int GetClientOfAuthId(const char[] steamid)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i) || !IsClientAuthorized(i))
			continue;

		decl String:steamidBuffer[MAX_STEAMID_LENGTH];
		GetClientAuthId(i, AuthId_Steam2, steamidBuffer, sizeof(steamidBuffer));

		if (StrEqual(steamid, steamidBuffer))
			return i;
	}
	return 0;
}
