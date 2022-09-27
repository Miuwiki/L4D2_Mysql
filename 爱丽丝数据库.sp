//#数据库需要手动建，插件无法建立。因为在连接的时候已经指定了数据库，所以无法后面再建立数据库。但是可以建立非config指定的数据库。
//#数据库只需要开头连接一次，接下来直接使用这个handle即可
//#目前没有发现手动关闭连接的函数，应该是插件结束(服务器重启，手动卸载)才会断开
//#常用三种查询入口，fastquery无回调，tquery回调进行操作，tquery回调仅检查错误（该回调通用SQLErrorCheckCallback）
//fastquery因为也要进行错误输出，因此跟tquery回调检查错误基本一致，只是一个使用SQL_FastQuery，一个使用SQL_TQuery


/*
 * 主要实现round_end,map_end才上传数据。
 */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2022.8.9"
#define DB_CFG_NAME "Miuwiki"

Database db = null;
ConVar g_gamemode;

int g_jointime[MAXPLAYERS];
int g_kill_infected[MAXPLAYERS];
int g_kill_hunter[MAXPLAYERS];
int g_kill_smoker[MAXPLAYERS];
int g_kill_charger[MAXPLAYERS];
int g_kill_jockey[MAXPLAYERS];
int g_kill_spitter[MAXPLAYERS];
int g_kill_boomer[MAXPLAYERS];
int g_kill_tank[MAXPLAYERS];
int g_kill_witch[MAXPLAYERS];
int g_headshot[MAXPLAYERS];

bool g_auth_status[MAXPLAYERS];


static const char g_errorlist[][] = 
{
    "设置'SET NAMES utf8mb4'时发生错误",
    "创建 'table' 表时发生错误",
    "插入新玩家数据时发生错误",
    "团灭，过关，最终过关上传数据时发生错误"
};
public Plugin myinfo =
{
	name = "爱丽丝数据库统计信息--",
	author = "萌新/爱丽丝",
	description = "爱丽丝数据库统计信息--",
	version = PLUGIN_VERSION,
	url = "http://www.miuwiki.site"
}
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if( late )
    {
        PrintToServer("插件不允许延迟加载！");
        return APLRes_Failure;
    }
    return APLRes_Success;
}

public void OnPluginStart()
{
    ConnectDB();
    HookEvent("player_death",Event_PlayerDeathInfo);
    HookEvent("infected_death",Event_InfectedDeathInfo);
    HookEvent("player_team",Event_PlayerChangeTeamInfo);
    HookEvent("round_start",Event_RoundStartInfo);
    HookEvent("round_end",Event_UpdatePlayerInfo);
    HookEvent("map_transition",Event_UpdatePlayerInfo);
    HookEvent("finale_vehicle_leaving",Event_UpdatePlayerInfo);
     
    RegConsoleCmd("sm_mrank",Cmd_ShowRankCallback);
    //模式检查
    g_gamemode = FindConVar("mp_gamemode");
    HookConVarChange(g_gamemode,Cvar_HookConvarChange);
}
public void OnConfigsExecuted()
{
    GetCvars();
}
void Cvar_HookConvarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}
void GetCvars()
{
    char gamemode[32];
    GetConVarString(g_gamemode,gamemode,sizeof(gamemode));
    if(StrContains(gamemode,"coop",false) == -1)
    {
        SetFailState("数据库仅在战役模式可以启动！");
        return;
    }
}
public void OnClientAuthorized(int client)
{
    if(CheckDBStatus() && !IsFakeClient(client))
    {
        char steam64[64];
        GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
        //检查玩家是否新进玩家or老玩家
        char query[512];
        Format(query, sizeof(query), "SELECT steam_id64 FROM player_info WHERE steam_id64 = '%s'", steam64);
        // 保险起见传递userid，毕竟有延迟
        int userid = GetClientUserId(client);
        SQL_TQuery(db, InsertPlayerToDB, query, userid);
        g_auth_status[client] = true;
    }
}
//玩家信息
public void OnClientConnected(int client)
{
    if(!IsFakeClient(client))
    {
        g_jointime[client] = GetTime();
        g_kill_infected[client] =0;
        g_kill_hunter[client] = 0;
        g_kill_smoker[client] = 0;
        g_kill_charger[client] = 0;
        g_kill_jockey[client] = 0;
        g_kill_spitter[client] = 0;
        g_kill_boomer[client] = 0;
        g_kill_tank[client] = 0;
        g_kill_witch[client] = 0;
        g_headshot[client] = 0;
        g_auth_status[client] = false;
    }
}
public void OnClientDisconnect(int client)
{
    if(!IsFakeClient(client))
    {
        g_jointime[client] = 0;
        g_kill_infected[client] =0;
        g_kill_hunter[client] = 0;
        g_kill_smoker[client] = 0;
        g_kill_charger[client] = 0;
        g_kill_jockey[client] = 0;
        g_kill_spitter[client] = 0;
        g_kill_boomer[client] = 0;
        g_kill_tank[client] = 0;
        g_kill_witch[client] = 0;
        g_headshot[client] = 0;
        g_auth_status[client] = false;
    }
}
void Event_RoundStartInfo(Event event,const char[] name,bool dontbroadcast)
{
    if( !CheckDBStatus() )
        return;

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsValidClient(client) && !IsFakeClient(client))
        {
            char steam64[64];
            GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
            char query[512];
            //select 不能分开写。
            Format(query, sizeof(query), "SELECT kill_special,kill_infected,headshots,time_totalplay,time_laston,uid FROM player_info WHERE steam_id64 = '%s'",steam64);
            int userid = GetClientUserId(client);
            SQL_TQuery(db, DisplayPanel, query, userid);
        }
    }
}
//上传数据 
void Event_UpdatePlayerInfo(Event event,const char[] name,bool dontbroadcast)
{
    if( strcmp(name,"round_end") == 0 )//团灭上传数据
    {
        PrintToChatAll("\x04[爱丽丝数据库]\x05过关失败! 正在为玩家保存数据...");
        UpdateChapterKillInfo();
    }
    if( strcmp(name,"map_transition") == 0 )//章节过关上传数据
    {
        PrintToChatAll("\x04[爱丽丝数据库]\x05完成章节! 正在为玩家保存数据...");
        UpdateChapterKillInfo();
    }
    if( strcmp(name,"finale_vehicle_leaving") == 0 )//最终章节过关上传数据
    {
        PrintToChatAll("\x04[爱丽丝数据库]\x05通关战役! 正在为玩家保存数据...");
        UpdateChapterKillInfo();
    }
}
//全局变量操作
void Event_PlayerDeathInfo(Event event,const char[] name,bool dontbroadcast)
{
    int attacker = GetClientOfUserId( event.GetInt("attacker") );
    int victim = GetClientOfUserId( event.GetInt("userid") );
    bool is_headshot = event.GetBool("headshot");
    char victim_name[64];
    event.GetString("victimname",victim_name,sizeof(victim_name));

    if( !IsValidClientNoTeam(victim) )
        return;

    if( IsValidClient(attacker) )
    {
        if (strcmp(victim_name, "Hunter") == 0)
        {
            g_kill_hunter[attacker]+=1;
        }
        else if (strcmp(victim_name, "Smoker") == 0)
        {
            g_kill_smoker[attacker]+=1;
        }
        else if (strcmp(victim_name, "Boomer") == 0)
        {
            g_kill_boomer[attacker]+=1;
        }
        else if (strcmp(victim_name, "Charger") == 0)
        {
            g_kill_charger[attacker]+=1;
        }
        else if (strcmp(victim_name, "Jockey") == 0)
        {
            g_kill_jockey[attacker]+=1;
        }
        else if (strcmp(victim_name, "Spitter") == 0)
        {
            g_kill_spitter[attacker]+=1;
        }
        if(is_headshot)
        {
            g_headshot[attacker]+=1;
        }
    }
}
void Event_InfectedDeathInfo(Event event,const char[] name,bool dontbroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if(IsValidClient(attacker)&&!IsFakeClient(attacker))
    {
        g_kill_infected[attacker] += 1;
    }
}
void Event_PlayerChangeTeamInfo(Event event,const char[] name,bool dontbroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event,"userid"));
    int newteam = GetEventInt(event,"team");
    int oldteam = GetEventInt(event,"oldteam");
    bool isbot = GetEventBool(event,"isbot");
    if( !isbot && 0 <= oldteam <= 1 && newteam == 2 )
    {
        PrintToChat(client,"\x04[爱丽丝数据库]:\x05统计数据仅在团灭和完成章节上传!使用指令\x04!mrank\x05查询战绩.");
        if(CheckDBStatus())
        {
            char steam64[64];
            GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
            int userid = GetClientUserId(client);
            if( g_auth_status[client] )
            {
                char query[512];
                //select 不能分开写。
                Format(query, sizeof(query), "SELECT kill_special,kill_infected,headshots,time_totalplay,time_laston,uid FROM player_info WHERE steam_id64 = '%s'",steam64);
                SQL_TQuery(db, DisplayPanel, query, userid);
            }
            else
            {
                CreateTimer(1.0,Timer_DisplayPanel,userid,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
            }
        }
    }
}
Action Cmd_ShowRankCallback(int client,int args)
{
    if( !IsValidClient(client) || !CheckDBStatus() )
        return Plugin_Continue;

    char steam64[64];
    GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
    char query[512];
    //select 不能分开写。
    Format(query, sizeof(query), "SELECT kill_special,kill_infected,headshots,time_totalplay,time_laston,uid FROM player_info WHERE steam_id64 = '%s'",steam64);
    int userid = GetClientUserId(client);
    SQL_TQuery(db, DisplayPanel, query, userid);

    return Plugin_Continue;
}
void DisplayPanel(Handle owner,Handle hndl,const char[] error,any data)
{
    int client = GetClientOfUserId(data);
    if( !IsValidClient(client))
        return;

    if( hndl == INVALID_HANDLE)
        return;
        
    int uid;int killspecial;int killinfected;int headshots;int time_totalplay;int time_laston;
    while(SQL_FetchRow(hndl))
    {
        killspecial = SQL_FetchInt(hndl, 0);
        killinfected = SQL_FetchInt(hndl, 1);
        headshots = SQL_FetchInt(hndl, 2);
        time_totalplay = SQL_FetchInt(hndl, 3);
        time_laston = SQL_FetchInt(hndl, 4);
        uid = SQL_FetchInt(hndl, 5);
    }
    float headrat = headshots == 0 ? 0.00 : float(headshots)/float(killspecial)*100;
    Panel panel_w = CreatePanel();
    char time[32],line[512];
    FormatTime(time,sizeof(time),"%F",time_laston);//%F来源：https://cplusplus.com/reference/ctime/strftime/
    Format(line,sizeof(line),"☆☆爱丽丝组——死门战役服☆☆\n—————————\nUid: %d %N\n上次光临: %s \n—————————",uid,client,time);
    panel_w.SetTitle(line);
    Format(line,sizeof(line),"击毙丧尸: %d 只",killinfected);
    panel_w.DrawText(line);
    Format(line,sizeof(line),"击毙特感: %d 只",killspecial);
    panel_w.DrawText(line);
    Format(line,sizeof(line),"爆头精准度: %.2f \%",headrat);
    panel_w.DrawText(line);
    Format(line,sizeof(line),"游玩总时长: %.2f h",float(time_totalplay)/3600);
    panel_w.DrawText(line);
    Format(line,sizeof(line),"—————————");
    panel_w.DrawText(line);
    Format(line,sizeof(line),"官网: http://miuwiki.site");
    panel_w.DrawText(line);
    Format(line,sizeof(line),"公开群: 522216503");
    panel_w.DrawText(line);
    panel_w.DrawItem("关闭");

    panel_w.Send(client,PanelCallback_panel_w,30);
    delete panel_w;
    
}
Action Timer_DisplayPanel(Handle timer,any userid)
{
    int client = GetClientOfUserId(userid);
    if(IsValidClient(client) && g_auth_status[client])
    {
        char steam64[64];
        GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
        char query[512];
        //select 不能分开写。
        Format(query, sizeof(query), "SELECT kill_special,kill_infected,headshots,time_totalplay,time_laston,uid FROM player_info WHERE steam_id64 = '%s'",steam64);
        SQL_TQuery(db, DisplayPanel, query, userid);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}
int PanelCallback_panel_w(Handle menu, MenuAction action,int param1,int param2)
{
    return 0;
}
void ConnectDB()
{
    if(SQL_CheckConfig(DB_CFG_NAME))
    {
        char error[255];
        //db = SQL_DefConnect(error, sizeof(error));//使用database.cfg里面的default数据进行连接
        db = SQL_Connect(DB_CFG_NAME,true,error,sizeof(error));//第二个参数为是否寻找并使用之前的连接，不开新的连接。找不到再开新的连接
        if(db == null)
        {
            SetFailState("连接数据库发生错误,%s",error);
            return;
        }
        else
        {
            char query[1024];
            Format(query,sizeof(query),"CREATE TABLE IF NOT EXISTS player_info ( \
                                        uid int(11) not null auto_increment,\
                                        steam_id32 varchar(64) not null,\
                                        steam_id64 varchar(64) not null,\
                                        player_name text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci not null,\
                                        time_laston int(11) not null,\
                                        time_totalplay int(11) not null,\
                                        headshots int(11) not null,\
                                        kill_special int(11) not null,\
                                        kill_infected int(11) not null,\
                                        kill_smoker int(11) not null,\
                                        kill_hunter int(11) not null,\
                                        kill_jockey int(11) not null,\
                                        kill_spitter int(11) not null,\
                                        kill_boomer int(11) not null,\
                                        kill_charger int(11) not null,\
                                        kill_tank int(11) not null,\
                                        kill_witch int(11) not null,\
                                        PRIMARY KEY (uid,steam_id64) );\
                                        ");
            // if(!SQL_FastQuery(db, query))
            // {
            //     char error[255];
            //     SQL_GetError(db,error,sizeof(error));
            //     LogError("[爱丽丝数据库提示-发生错误]: %s,\n出现位置: create table创建表的时候",error);
            // }//与下面用法基本一致，只是不需要重新写一行错误输出。
            SendSQLUpdate(query,1);
        }
    }
    else
    {
        LogError("[爱丽丝数据库-发生错误]: 未配置database.cfg,请前往config文件夹配置一个名为Miuwiki的数据库样板。");
    }
}
//SQL_TQuery回调一般格式，owner是db的handle，hndl是TQuery的handle，data传递为userid
void InsertPlayerToDB(Handle owner,Handle hndl,const char[] error,any data)
{
    int client = GetClientOfUserId(data);
    char steam32[64],steam64[64];
    GetClientAuthId(client,AuthId_SteamID64,steam64,sizeof(steam64));
    GetClientAuthId(client,AuthId_Steam2,steam32,sizeof(steam32));
    if(CheckDBStatus() && hndl != null && 1<= client <=31 )
    {
        if(!SQL_GetRowCount(hndl))//新玩家找不到，返回0，取反1判断true
        {
            char query[512];
            //避免主键冲突报错INSERT IGNORE INTO ，但是我们不用
            Format(query, sizeof(query), "INSERT INTO player_info SET steam_id64 = '%s'", steam64);
            SendSQLUpdate(query,2);
        }
    }
    //避免数据库注入
    char Name[256],query[512];
    GetClientName(client, Name, sizeof(Name));
    ReplaceString(Name, sizeof(Name), "<?php", "");
    ReplaceString(Name, sizeof(Name), "<?PHP", "");
    ReplaceString(Name, sizeof(Name), "?>", "");
    ReplaceString(Name, sizeof(Name), "\\", "");
    ReplaceString(Name, sizeof(Name), "\"", "");
    ReplaceString(Name, sizeof(Name), "'", "");
    ReplaceString(Name, sizeof(Name), ";", "");
    ReplaceString(Name, sizeof(Name), "?", "");
    ReplaceString(Name, sizeof(Name), "`", "");

    Format(query,sizeof(query),"SET NAMES utf8mb4");
    SendSQLUpdate(query,0);

    Format(query, sizeof(query), "UPDATE player_info SET \
                                steam_id32 = '%s', \
                                player_name = '%s' \
                                WHERE steam_id64 = '%s'", steam32,Name, steam64);
    SendSQLUpdate(query,3);
}
void UpdateChapterKillInfo()
{
    for(int i=1; i<=MaxClients; i++)
    {
        if(IsClientInGame(i)&& !IsFakeClient(i) )
        {
            int playtime = GetTime()-g_jointime[i];
            char steam64[64];
            GetClientAuthId(i,AuthId_SteamID64,steam64,sizeof(steam64));
            char Name[256];
            GetClientName(i, Name, sizeof(Name));
            ReplaceString(Name, sizeof(Name), "<?php", "");
            ReplaceString(Name, sizeof(Name), "<?PHP", "");
            ReplaceString(Name, sizeof(Name), "?>", "");
            ReplaceString(Name, sizeof(Name), "\\", "");
            ReplaceString(Name, sizeof(Name), "\"", "");
            ReplaceString(Name, sizeof(Name), "'", "");
            ReplaceString(Name, sizeof(Name), ";", "");
            ReplaceString(Name, sizeof(Name), "?", "");
            ReplaceString(Name, sizeof(Name), "`", "");
            char query[1024];

            Format(query,sizeof(query),"SET NAMES 'utf8mb4'");
            SendSQLUpdate(query,0);
            
            Format(query, sizeof(query), "UPDATE player_info SET \
                                        time_laston = '%d', \
                                        time_totalplay = time_totalplay + %d,\
                                        player_name = '%s', \
                                        headshots = headshots + '%d',\
                                        kill_infected = kill_infected + '%d',\
                                        kill_smoker = kill_smoker + '%d',\
                                        kill_hunter = kill_hunter + '%d',\
                                        kill_jockey = kill_jockey + '%d',\
                                        kill_spitter = kill_spitter + '%d',\
                                        kill_boomer = kill_boomer + '%d',\
                                        kill_charger = kill_charger + '%d',\
                                        kill_witch = kill_witch + '%d',\
                                        kill_tank = kill_tank + '%d',\
                                        kill_special = kill_smoker + kill_hunter + kill_jockey + kill_spitter + kill_boomer + kill_charger + kill_tank + kill_witch \
                                        WHERE steam_id64 = '%s'", 
                                        GetTime(),playtime,Name,g_headshot[i],g_kill_infected[i],g_kill_smoker[i],g_kill_hunter[i],
                                        g_kill_jockey[i],g_kill_spitter[i],g_kill_boomer[i],g_kill_charger[i],
                                        g_kill_witch[i],g_kill_tank[i],
                                        steam64);
            SendSQLUpdate(query,3);                        
        }
    }
}
// --------------------------------------------
/*
 * 回调仅检查错误的SQL_TQuery.
 * 对于无需进行后续操作的查询，使用这个作为函数名多线程查询入口，并在index指出错误发生的地方。
 * @param query 		查询语句
 * @param error_index   错误合集索引.错误合集g_errorlist.
 */
void SendSQLUpdate(char[] query,int error_index)
{
    if(db == null)
        return;

    SQL_TQuery(db,SQLErrorCheckCallback,query,error_index);
}
void SQLErrorCheckCallback(Handle owner, Handle hndl, const char[] error, any data)
{
    if(db == null)
        return;

    if(!StrEqual("", error))
        LogError("[爱丽丝数据库-发生错误]: %s,\n出现位置: %s,错误索引:%d", error,g_errorlist[data],data);
}
/*
 * 仅一处连接，不需要传递DB
 * @return db == null ,返回false；db != null,返回 true。
 */
bool CheckDBStatus()
{
    if(db == null)
        return false;
    return true;
}
bool IsValidClient(int client)
{
    if(1<= client <= 32)
    {
        if(IsClientInGame(client))
        {
            if(GetClientTeam(client)==2)
            {
                return true;
            }
        }
    }
    return false;
}
bool IsValidClientNoTeam(int client)
{
    if( client>=1 &&client <= MaxClients)
    {
        if(IsClientInGame(client))
        {
            return true;
        }
    }
    return false;
}
