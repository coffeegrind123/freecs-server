/*
 * YaPB for FreeCS — QuakeC port of YaPB bot AI
 * Based on YaPB by YaPB Project Developers (MIT License)
 *
 * yapb_bot.h — Main bot class definition (extends ncBot)
 */

#include "constants.h"

/* Difficulty data — reaction times, headshot chance, etc. */
typedef struct {
	float reactionTime[2]; /* min, max */
	float headshotPct;
	float seenThruWallPct;
	float hearingPct;
	int maxRecoilDegrees;
	float aimError[2]; /* min, max */
} yapb_difficulty_t;

/* Bot task entry */
typedef struct {
	int id;
	float desire;
	int data;
	float time;
	bool resume;
} yapb_task_t;

/* Maximum stacked tasks */
#define MAX_TASKS 16

class yapbBot:ncBot
{
public:
	void yapbBot(void);

	/* Nuclide overrides */
	virtual void RunAI(void);
	virtual void CreateObjective(void);
	virtual void WeaponThink(void);
	virtual void SeeThink(entity, bool);
	virtual void BrainThink(int, int);
	virtual void CheckRoute(void);
	virtual void PostFrame(void);

	/* YaPB task system */
	nonvirtual void TaskPush(int taskId, float desire, int data, float time, bool resume);
	nonvirtual void TaskPop(void);
	nonvirtual int TaskGetCurrent(void);
	nonvirtual float TaskGetDesire(void);
	nonvirtual void TasksClear(void);

	/* YaPB combat */
	nonvirtual void CombatThink(void);
	nonvirtual bool ReactOnEnemy(void);
	nonvirtual bool IsEnemyThreat(entity ent);
	nonvirtual void SelectBestWeapon(void);
	nonvirtual void BuyStuff(void);
	nonvirtual void FireWeapon(void);
	nonvirtual void AimAtEnemy(void);

	/* YaPB navigation */
	nonvirtual void FindBestGoal(void);
	nonvirtual void ExecuteMovement(void);
	nonvirtual void CheckStuck(void);
	nonvirtual void AvoidObstacles(void);

	/* YaPB sensing */
	nonvirtual bool IsEnemyVisible(entity ent);
	nonvirtual bool IsInViewCone(entity ent, float fov);
	nonvirtual void LookupEnemies(void);
	nonvirtual void ListenForSounds(void);

	/* YaPB decision making */
	nonvirtual void DecideGoal(void);
	nonvirtual bool ShouldCamp(void);
	nonvirtual bool ShouldDefuse(void);
	nonvirtual bool ShouldPlant(void);
	nonvirtual bool ShouldRetreat(void);

	/* --- Member variables --- */

	/* Personality & difficulty */
	int m_personality;
	int m_difficulty;
	yapb_difficulty_t m_diffData;

	/* Task stack */
	yapb_task_t m_tasks[MAX_TASKS];
	int m_taskCount;

	/* Combat state */
	entity m_enemy;
	entity m_lastEnemy;
	vector m_enemyOrigin;
	vector m_lastEnemyOrigin;
	float m_enemyUpdateTime;
	float m_seeEnemyTime;
	float m_shootTime;
	float m_reloadTime;
	int m_aimFlags;
	vector m_lookAt;

	/* Sensing */
	int m_states;
	float m_heardSoundTime;
	vector m_heardSoundPos;

	/* Navigation */
	vector m_destOrigin;
	int m_collisionState;
	float m_stuckCheckTime;
	vector m_prevOrigin;
	float m_prevSpeed;
	int m_stuckCount;
	float m_campStartTime;
	float m_campEndTime;

	/* Economy */
	int m_money;
	bool m_hasBought;

	/* Timing */
	float m_thinkInterval;
	float m_lastThinkTime;
	float m_reactionTime;
	float m_aggression;
	float m_fear;

	/* Misc */
	bool m_isVIP;
	bool m_hasBomb;
	bool m_hasDefuseKit;
	float m_spawnTime;
	string m_botName;
};
