#include <sourcemod>
#include <sdktools>

#pragma newdecls required

const int MAX_BOSSES = 7;
static const char Model[] = "models/error.mdl";

enum struct BW_BossData
{
    int BossEntity;
    int ParentEntity;

    int HammerID;
    char Name[64];
    char Targetname[64];
    float ShiftPosition[3];
    float RotateAngles[3];
}

bool Toggle;
int Bosses;
int ClientBossWatching[MAXPLAYERS + 1] = {-1, ...};
BW_BossData BossesData[MAX_BOSSES];

Menu BossesMenu;

public void OnPluginStart()
{
    BossesMenu = new Menu(BossesMenuH, MenuAction_DisplayItem|MenuAction_DrawItem|MenuAction_Select);
    BossesMenu.SetTitle("Boss Watching");
    RegConsoleCmd("sm_boss", Command_BossWatching);
    RegConsoleCmd("sm_specboss", Command_BossWatching);
}

public void OnPluginEnd()
{
    if(Toggle == false)
    {
        return;
    }
    for(int i; i < Bosses; i++)
    {
        if(BossesData[i].ParentEntity > 0 && IsValidEntity(BossesData[i].ParentEntity))
        {
            RemoveEntity(BossesData[i].ParentEntity);
        }
    }
}

public void OnMapStart()
{
    char szBuffer[256];
    GetCurrentMap(szBuffer, 256);
    StringToLowerCase(szBuffer);
    BuildPath(Path_SM, szBuffer, 256, "configs/bosswatching/%s.cfg", szBuffer);
    KeyValues hKeyValues = new KeyValues("Bosses");

    if(!hKeyValues.ImportFromFile(szBuffer) || !hKeyValues.GotoFirstSubKey())
    {
        LogMessage("Config file \"%s\" not founded", szBuffer);
        return;
    }
    PrecacheModel(Model, true);
    int iCount;
    do
    {
        BossesData[iCount].HammerID = hKeyValues.GetNum("HammerID");
        hKeyValues.GetString("Name", BossesData[iCount].Name, 64);
        hKeyValues.GetString("Targetname", BossesData[iCount].Targetname, 64);
        hKeyValues.GetVector("ShiftPosition", BossesData[iCount].ShiftPosition);
        hKeyValues.GetVector("RotateAngles", BossesData[iCount].RotateAngles);
        BossesMenu.AddItem(BossesData[iCount].Name, BossesData[iCount].Name);
        iCount++;
    }
    while(hKeyValues.GotoNextKey() && iCount < MAX_BOSSES);
    delete hKeyValues;

    Bosses = iCount;

    Toggle = (Bosses > 0);
}

public void OnMapEnd()
{
    Toggle = false;
    Bosses = 0;
    BossesMenu.RemoveAllItems();
}

public void OnEntitySpawned(int entity, const char[] classname)
{
    if(Toggle == false || !IsValidEntity(entity))
    {
        return;
    }
    static int iHammerID;
    static char szTargetName[64];
    iHammerID = GetEntProp(entity, Prop_Data, "m_iHammerID");
    GetEntPropString(entity, Prop_Data, "m_iName", szTargetName, 64);

    for(int i; i < Bosses; i++)
    {
        if( (iHammerID && iHammerID == BossesData[i].HammerID) ||
            (szTargetName[0] && !strcmp(szTargetName, BossesData[i].Targetname, false)))
        {
            BossesData[i].BossEntity = entity;
            Boss_CreateParentEntity(i);
            return;
        }
    }
}

public void OnEntityDestroyed(int entity)
{
    if(Toggle == false || entity == 0)
    {
        return;
    }
    for(int i; i < Bosses; i++)
    {
        if(BossesData[i].BossEntity == entity || BossesData[i].ParentEntity == entity)
        {
            BossesData[i].BossEntity = 0;
            BossesData[i].ParentEntity = 0;
            Boss_DisableWatchingAll(i);
            break;
        }
    }
}

public Action Command_BossWatching(int iClient, int iArgs)
{
    if(Toggle == false)
    {
        return Plugin_Handled;
    }

    BossesMenu.Display(iClient, 0);
    return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
    ClientBossWatching[client] = -1;
}

public int BossesMenuH(Menu hMenu, MenuAction action, int iClient, int iItem)
{
    switch(action)
    {
        case MenuAction_DisplayItem:
        {
            if(ClientBossWatching[iClient] == iItem)
            {
                char szBuffer[128];
                hMenu.GetItem(iItem, "", 0, _, szBuffer, 128);
                Format(szBuffer, 128, "%s [X]", szBuffer);
                RedrawMenuItem(szBuffer);
            }
        }
        case MenuAction_DrawItem:
        {
            return BossesData[iItem].ParentEntity ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED;
        }
        case MenuAction_Select:
        {
            if(ClientBossWatching[iClient] == iItem)
            {
                Boss_DisableWatching(iClient);
            }
            else
            {
                Boss_EnableWatching(iClient, iItem);
            }
            hMenu.DisplayAt(iClient, hMenu.Selection, 0);
        }
    }

    return 0;
}

stock void Boss_CreateParentEntity(int iBossID)
{
    int entity = CreateEntityByName("prop_dynamic");

    if(entity != -1)
    {
        char szBuffer[64];
        FormatEx(szBuffer, 64, "bw_%i", entity);
        DispatchKeyValue(entity, "targetname", szBuffer);
        DispatchKeyValue(entity, "solid", "0");
        DispatchKeyValue(entity, "model", Model);
        DispatchKeyValue(entity, "spawnflags", "256");
        DispatchKeyValue(entity, "rendermode", "10");

        if(DispatchSpawn(entity))
        {
            float fPos[3];
            float fAng[3];
            Boss_FixCoordinates(iBossID, fPos, fAng);
            TeleportEntity(entity, fPos, fAng, NULL_VECTOR);
            SetVariantString("!activator");
            AcceptEntityInput(entity, "SetParent", BossesData[iBossID].BossEntity); 
            BossesData[iBossID].ParentEntity = entity;
        }
    }
}

/*stock void BossMenu_UpdateClientsMenu()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && GetClientMenu(i) == BossesMenu)
        {
            BossesMenu.Display(i, 0);
        }
    }
}*/

stock void Boss_EnableWatching(int iClient, int iBossID)
{
    ClientBossWatching[iClient] = iBossID;
    SetClientViewEntity(iClient, BossesData[iBossID].ParentEntity);
}

stock void Boss_DisableWatchingAll(int iBossID)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(ClientBossWatching[i] == iBossID)
        {
            Boss_DisableWatching(i);
        }
    }
}

stock void Boss_DisableWatching(int iClient)
{
    ClientBossWatching[iClient] = -1;
    SetClientViewEntity(iClient, iClient);
}

stock void Boss_FixCoordinates(int iBossID, float fPos[3], float fAng[3])
{
    GetEntPropVector(BossesData[iBossID].BossEntity, Prop_Data, "m_vecOrigin", fPos);
    GetEntPropVector(BossesData[iBossID].BossEntity, Prop_Data, "m_angRotation", fAng);
    for(int i; i < 3; i++)
    {
        fPos[i] += BossesData[iBossID].ShiftPosition[i];
        fAng[i] += BossesData[iBossID].RotateAngles[i];
    }
}

stock void StringToLowerCase(char[] buffer)
{
    int len = strlen(buffer);
    for(int i; i < len; i++)
    {
        if(IsCharUpper(buffer[i]))
        {
            CharToLower(buffer[i]);
        }
    }
}