/*
 * YaPB for FreeCS — QuakeC port of YaPB bot AI
 * Based on YaPB by YaPB Project Developers (MIT License)
 *
 * yapb_bot.qc — Core bot class implementation
 */

#include "yapb_bot.h"

/* Difficulty presets — from YaPB difficulty.cfg defaults */
static yapb_difficulty_t g_difficultyData[] = {
	{ {0.8, 1.5}, 0.0,  0.0,  0.3, 16, {50.0, 80.0} },  /* Noob */
	{ {0.4, 0.8}, 0.1,  0.0,  0.5, 12, {30.0, 50.0} },  /* Easy */
	{ {0.2, 0.5}, 0.3,  0.1,  0.7,  8, {15.0, 30.0} },  /* Normal */
	{ {0.1, 0.3}, 0.6,  0.2,  0.9,  4, { 5.0, 15.0} },  /* Hard */
	{ {0.0, 0.1}, 0.9,  0.4,  1.0,  0, { 0.0,  5.0} }   /* Expert */
};

void
yapbBot::yapbBot(void)
{
	m_personality = PERSONALITY_NORMAL;
	m_difficulty = DIFFICULTY_NORMAL;
	m_diffData = g_difficultyData[m_difficulty];
	m_taskCount = 0;
	m_enemy = __NULL__;
	m_lastEnemy = __NULL__;
	m_aimFlags = AIM_NAVPOINT;
	m_states = 0;
	m_collisionState = COLLISION_UNDECIDED;
	m_stuckCount = 0;
	m_money = 800;
	m_hasBought = false;
	m_aggression = 0.0;
	m_fear = 0.0;
	m_spawnTime = time;
	m_lastThinkTime = time;
	m_thinkInterval = 0.0;

	/* start with the normal task */
	TaskPush(TASK_NORMAL, TASKPRI_NORMAL, -1, 0.0, true);
}

/*
 * RunAI — Main bot think loop. Called every server frame by Nuclide.
 * This is the equivalent of YaPB's BotFrame() function.
 */
void
yapbBot::RunAI(void)
{
	/* respect reaction time based on difficulty */
	if (time - m_lastThinkTime < m_thinkInterval)
		return;

	m_lastThinkTime = time;
	m_thinkInterval = m_diffData.reactionTime[0] +
		random() * (m_diffData.reactionTime[1] - m_diffData.reactionTime[0]);

	/* clamp to minimum think rate */
	if (m_thinkInterval < 0.02)
		m_thinkInterval = 0.02;

	/* update aggression/fear based on personality */
	switch (m_personality) {
	case PERSONALITY_RUSHER:
		m_aggression = bound(0.0, m_aggression + 0.1, 1.0);
		m_fear = bound(0.0, m_fear - 0.05, 1.0);
		break;
	case PERSONALITY_CAREFUL:
		m_aggression = bound(0.0, m_aggression - 0.05, 1.0);
		m_fear = bound(0.0, m_fear + 0.1, 1.0);
		break;
	default:
		break;
	}

	/* phase 1: sense the world */
	LookupEnemies();
	ListenForSounds();

	/* phase 2: buy equipment if we haven't */
	if (m_hasBought == false && time > m_spawnTime + 2.0) {
		BuyStuff();
		m_hasBought = true;
	}

	/* phase 3: run the current task */
	int task = TaskGetCurrent();

	switch (task) {
	case TASK_NORMAL:
		/* default behavior: find a goal and move to it */
		if (m_states & STATE_SEEING_ENEMY) {
			TaskPush(TASK_ATTACK, TASKPRI_ATTACK, -1, 0.0, true);
		} else {
			DecideGoal();
			ExecuteMovement();
		}
		break;

	case TASK_ATTACK:
		if (m_enemy == __NULL__ || m_enemy.health <= 0) {
			TaskPop();
			break;
		}
		CombatThink();
		break;

	case TASK_SEEKCOVER:
		if (!(m_states & STATE_SEEING_ENEMY)) {
			TaskPop();
			break;
		}
		/* TODO: find cover position and move to it */
		ExecuteMovement();
		break;

	case TASK_CAMP:
		if (m_campEndTime > 0.0 && time >= m_campEndTime) {
			TaskPop();
			break;
		}
		/* hold position, look around */
		input_movevalues = [0, 0, 0];
		break;

	case TASK_MOVETOPOSITION:
		ExecuteMovement();
		break;

	case TASK_FOLLOWUSER:
		/* TODO: follow a specific player */
		ExecuteMovement();
		break;

	case TASK_PICKUPITEM:
		ExecuteMovement();
		break;

	case TASK_PLANTBOMB:
		/* TODO: bomb plant logic */
		break;

	case TASK_DEFUSEBOMB:
		/* TODO: bomb defuse logic */
		break;

	case TASK_HUNT:
		/* hunt last known enemy position */
		if (m_lastEnemy == __NULL__ || time > m_seeEnemyTime + 10.0) {
			TaskPop();
			break;
		}
		RouteToPosition(m_lastEnemyOrigin);
		ExecuteMovement();
		break;

	case TASK_ESCAPEFROMBOMB:
		/* TODO: run away from planted bomb */
		ExecuteMovement();
		break;

	case TASK_HIDE:
		input_movevalues = [0, 0, 0];
		if (time > m_campEndTime) {
			TaskPop();
		}
		break;

	default:
		TaskPop();
		break;
	}

	/* phase 4: update aim */
	AimAtEnemy();

	/* phase 5: check if we're stuck */
	CheckStuck();
}

/*
 * CreateObjective — Called by Nuclide when bot needs a new goal.
 */
void
yapbBot::CreateObjective(void)
{
	FindBestGoal();
}

/*
 * PostFrame — Called after physics. Update states.
 */
void
yapbBot::PostFrame(void)
{
	m_prevOrigin = origin;
}

/* === TASK SYSTEM === */

void
yapbBot::TaskPush(int taskId, float desire, int data, float taskTime, bool resume)
{
	if (m_taskCount >= MAX_TASKS)
		return;

	/* insert sorted by desire (highest first) */
	int insertAt = m_taskCount;
	for (int i = 0; i < m_taskCount; i++) {
		if (desire > m_tasks[i].desire) {
			insertAt = i;
			break;
		}
	}

	/* shift everything down */
	for (int i = m_taskCount; i > insertAt; i--) {
		m_tasks[i] = m_tasks[i - 1];
	}

	m_tasks[insertAt].id = taskId;
	m_tasks[insertAt].desire = desire;
	m_tasks[insertAt].data = data;
	m_tasks[insertAt].time = taskTime > 0.0 ? time + taskTime : 0.0;
	m_tasks[insertAt].resume = resume;
	m_taskCount++;
}

void
yapbBot::TaskPop(void)
{
	if (m_taskCount <= 0)
		return;

	/* remove highest priority task (index 0) */
	for (int i = 0; i < m_taskCount - 1; i++) {
		m_tasks[i] = m_tasks[i + 1];
	}
	m_taskCount--;

	/* always have at least the normal task */
	if (m_taskCount <= 0) {
		TaskPush(TASK_NORMAL, TASKPRI_NORMAL, -1, 0.0, true);
	}
}

int
yapbBot::TaskGetCurrent(void)
{
	if (m_taskCount <= 0)
		return TASK_NORMAL;
	return m_tasks[0].id;
}

float
yapbBot::TaskGetDesire(void)
{
	if (m_taskCount <= 0)
		return 0.0;
	return m_tasks[0].desire;
}

void
yapbBot::TasksClear(void)
{
	m_taskCount = 0;
	TaskPush(TASK_NORMAL, TASKPRI_NORMAL, -1, 0.0, true);
}
