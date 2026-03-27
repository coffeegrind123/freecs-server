/*
 * YaPB for FreeCS — QuakeC port of YaPB bot AI
 * Based on YaPB by YaPB Project Developers (MIT License)
 *
 * navigate.qc — Pathfinding, goal selection, movement execution
 */

#include "yapb_bot.h"

/*
 * FindBestGoal — Select the best navigation goal based on game state.
 * From YaPB's findBestGoal() in tasks.cpp.
 *
 * Uses Nuclide's RouteToPosition() for actual pathfinding.
 */
void
yapbBot::FindBestGoal(void)
{
	/* don't recalculate too often */
	if (vlen(m_destOrigin - origin) > 128.0)
		return;

	/* pick a goal based on game situation */
	DecideGoal();

	/* route to the chosen destination */
	if (m_destOrigin != '0 0 0') {
		RouteToPosition(m_destOrigin);
	}
}

/*
 * DecideGoal — YaPB's tactical goal selection.
 * Considers map type, team, bomb status, personality.
 */
void
yapbBot::DecideGoal(void)
{
	/* heard an enemy? investigate */
	if (m_states & STATE_HEARING_ENEMY) {
		m_destOrigin = m_heardSoundPos;
		return;
	}

	/* should we camp? */
	if (ShouldCamp()) {
		m_campStartTime = time;
		m_campEndTime = time + 10.0 + random() * 20.0;
		TaskPush(TASK_CAMP, TASKPRI_CAMP, -1, m_campEndTime - time, false);
		return;
	}

	/* default: pick a random waypoint destination */
	Route_SelectDestination();
	m_destOrigin = PathDestination();
}

/*
 * ExecuteMovement — Move along the current path.
 * Uses Nuclide's CheckRoute() for node following.
 */
void
yapbBot::ExecuteMovement(void)
{
	/* let Nuclide handle the actual pathfollowing */
	CheckRoute();

	/* get movement direction from path */
	vector moveDir = Route_GetDirection();
	if (moveDir != '0 0 0') {
		makevectors(v_angle);

		/* project desired direction onto our forward/right vectors */
		float fwd = moveDir * v_forward;
		float rgt = moveDir * v_right;

		input_movevalues[0] = fwd * GetForwardSpeed();
		input_movevalues[1] = rgt * GetSideSpeed();
	}

	/* handle node flags */
	int nodeFlags = Route_GetNodeFlags();

	if (nodeFlags & ROUTE_JUMP) {
		input_buttons |= INPUT_JUMP;
	}
	if (nodeFlags & ROUTE_CROUCH) {
		input_buttons |= INPUT_CROUCH;
	}
	if (nodeFlags & ROUTE_USE) {
		input_buttons |= INPUT_USE;
	}
}

/*
 * CheckStuck — Detect and resolve stuck situations.
 * From YaPB's stuck detection in navigate.cpp.
 */
void
yapbBot::CheckStuck(void)
{
	if (time < m_stuckCheckTime)
		return;

	m_stuckCheckTime = time + 0.5;

	float speed = vlen(origin - m_prevOrigin);

	if (speed < 10.0 && input_movevalues[0] > 0) {
		m_stuckCount++;

		if (m_stuckCount > 3) {
			/* try jumping */
			input_buttons |= INPUT_JUMP;
		}
		if (m_stuckCount > 6) {
			/* try crouching */
			input_buttons |= INPUT_CROUCH;
		}
		if (m_stuckCount > 10) {
			/* try strafing */
			if (random() < 0.5)
				input_movevalues[1] = GetSideSpeed();
			else
				input_movevalues[1] = -GetSideSpeed();
		}
		if (m_stuckCount > 15) {
			/* give up on current path, pick new goal */
			RouteClear();
			m_stuckCount = 0;
			TasksClear();
		}
	} else {
		m_stuckCount = 0;
	}

	m_prevOrigin = origin;
}

/*
 * AvoidObstacles — Simple obstacle avoidance via tracing.
 */
void
yapbBot::AvoidObstacles(void)
{
	makevectors(v_angle);

	/* trace forward */
	vector fwdEnd = origin + v_forward * 64.0;
	traceline(origin, fwdEnd, MOVE_NORMAL, this);

	if (trace_fraction < 1.0) {
		/* obstacle ahead — try to go around */
		m_collisionState = COLLISION_PROBING;

		/* trace left */
		vector leftEnd = origin - v_right * 64.0;
		traceline(origin, leftEnd, MOVE_NORMAL, this);
		float leftFrac = trace_fraction;

		/* trace right */
		vector rightEnd = origin + v_right * 64.0;
		traceline(origin, rightEnd, MOVE_NORMAL, this);
		float rightFrac = trace_fraction;

		if (leftFrac > rightFrac) {
			input_movevalues[1] = -GetSideSpeed();
			m_collisionState = COLLISION_STRAFELEFT;
		} else {
			input_movevalues[1] = GetSideSpeed();
			m_collisionState = COLLISION_STRAFERIGHT;
		}
	} else {
		m_collisionState = COLLISION_UNDECIDED;
	}
}

/*
 * ShouldCamp — Decide if bot should camp at current position.
 * Based on personality, map position, and game state.
 */
bool
yapbBot::ShouldCamp(void)
{
	/* rushers don't camp */
	if (m_personality == PERSONALITY_RUSHER)
		return false;

	/* careful bots camp more often */
	float campChance = 0.05;
	if (m_personality == PERSONALITY_CAREFUL)
		campChance = 0.15;

	/* lower health = more likely to camp */
	if (health < 50)
		campChance += 0.1;

	return (random() < campChance);
}

/*
 * ShouldDefuse — Should the CT bot go defuse the bomb?
 */
bool
yapbBot::ShouldDefuse(void)
{
	if (team != 2) /* not CT */
		return false;

	/* TODO: check if bomb is planted via serverinfo */
	return false;
}

/*
 * ShouldPlant — Should the T bot plant the bomb?
 */
bool
yapbBot::ShouldPlant(void)
{
	if (team != 1) /* not T */
		return false;

	if (!m_hasBomb)
		return false;

	/* TODO: check if in bomb zone */
	return false;
}

/*
 * WeaponThink — Override Nuclide's weapon management.
 */
void
yapbBot::WeaponThink(void)
{
	/* let the combat system handle weapons */
}

/*
 * SeeThink — Override Nuclide's enemy detection with ours.
 */
void
yapbBot::SeeThink(entity target, bool visible)
{
	/* handled by LookupEnemies() */
}

/*
 * BrainThink — Override Nuclide's decision making.
 */
void
yapbBot::BrainThink(int enemyVisible, int enemyDist)
{
	/* handled by RunAI() task system */
}

/*
 * CheckRoute — Override to add stuck detection.
 */
void
yapbBot::CheckRoute(void)
{
	super::CheckRoute();
	AvoidObstacles();
}
