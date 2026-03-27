/*
 * YaPB for FreeCS — QuakeC port of YaPB bot AI
 * Based on YaPB by YaPB Project Developers (MIT License)
 *
 * combat.qc — Enemy detection, aiming, weapon selection, firing
 */

#include "yapb_bot.h"

/*
 * LookupEnemies — Scan for visible enemies. From YaPB vision.cpp.
 */
void
yapbBot::LookupEnemies(void)
{
	entity bestEnemy = __NULL__;
	float bestDist = 99999.0;

	for (entity e = world; (e = find(e, ::classname, "player"));) {
		if (e == this)
			continue;
		if (e.health <= 0)
			continue;
		if (e.team == this.team)
			continue;

		if (!IsEnemyVisible(e))
			continue;

		float dist = vlen(e.origin - origin);
		if (dist < bestDist) {
			bestDist = dist;
			bestEnemy = e;
		}
	}

	if (bestEnemy != __NULL__) {
		m_enemy = bestEnemy;
		m_enemyOrigin = bestEnemy.origin;
		m_seeEnemyTime = time;
		m_states |= STATE_SEEING_ENEMY;
	} else {
		if (time > m_seeEnemyTime + 4.0) {
			m_states &= ~STATE_SEEING_ENEMY;
		}
		if (m_enemy != __NULL__ && m_enemy.health > 0) {
			m_lastEnemy = m_enemy;
			m_lastEnemyOrigin = m_enemyOrigin;
		}
		m_enemy = __NULL__;
	}
}

/*
 * IsEnemyVisible — Line of sight + FOV check. From YaPB vision.cpp.
 */
bool
yapbBot::IsEnemyVisible(entity ent)
{
	if (ent == __NULL__)
		return false;

	/* FOV check first (cheaper than trace) */
	if (!IsInViewCone(ent, 75.0))
		return false;

	/* trace line to enemy */
	traceline(origin + view_ofs, ent.origin, MOVE_NORMAL, this);

	if (trace_ent == ent || trace_fraction >= 1.0)
		return true;

	/* try head position */
	traceline(origin + view_ofs, ent.origin + ent.view_ofs, MOVE_NORMAL, this);

	if (trace_ent == ent || trace_fraction >= 1.0)
		return true;

	return false;
}

/*
 * IsInViewCone — Check if entity is within bot's field of view.
 */
bool
yapbBot::IsInViewCone(entity ent, float fov)
{
	makevectors(v_angle);
	vector dir = normalize(ent.origin - origin);
	float dot = dir * v_forward;
	float halfFov = fov / 2.0;
	float threshold = cos(halfFov * (M_PI / 180.0));
	return (dot >= threshold);
}

/*
 * ListenForSounds — React to nearby gunfire/explosions.
 */
void
yapbBot::ListenForSounds(void)
{
	/* hearing based on difficulty */
	if (random() > m_diffData.hearingPct)
		return;

	/* check for nearby gunfire — simplified from YaPB sounds.cpp */
	for (entity e = world; (e = find(e, ::classname, "player"));) {
		if (e == this || e.team == this.team)
			continue;
		if (e.health <= 0)
			continue;

		float dist = vlen(e.origin - origin);
		if (dist > 1500.0)
			continue;

		/* if they're shooting (button0 pressed), we can hear them */
		if (e.button0 && dist < 1000.0) {
			m_heardSoundPos = e.origin;
			m_heardSoundTime = time;
			m_states |= STATE_HEARING_ENEMY;
			return;
		}
	}

	if (time > m_heardSoundTime + 5.0) {
		m_states &= ~STATE_HEARING_ENEMY;
	}
}

/*
 * CombatThink — Main combat loop. From YaPB combat.cpp reactOnEnemy().
 */
void
yapbBot::CombatThink(void)
{
	if (m_enemy == __NULL__ || m_enemy.health <= 0)
		return;

	m_aimFlags |= AIM_ENEMY;

	/* select weapon if we haven't */
	SelectBestWeapon();

	/* fire at enemy */
	FireWeapon();

	/* strafe during combat based on difficulty */
	float enemyDist = vlen(m_enemy.origin - origin);

	if (m_difficulty >= DIFFICULTY_NORMAL) {
		/* strafe left/right */
		float strafeDir = (random() < 0.5) ? -1.0 : 1.0;
		input_movevalues[1] = strafeDir * GetSideSpeed();
	}

	/* rush or retreat based on personality */
	if (m_aggression > m_fear && enemyDist > 200.0) {
		/* rush toward enemy */
		input_movevalues[0] = GetForwardSpeed();
	} else if (m_fear > m_aggression && enemyDist < 300.0) {
		/* back away */
		input_movevalues[0] = -GetBackSpeed();
	}

	/* crouch at medium range for accuracy */
	if (enemyDist > 400.0 && enemyDist < 800.0 && m_difficulty >= DIFFICULTY_HARD) {
		input_buttons |= INPUT_CROUCH;
	}

	/* check if we should retreat */
	if (ShouldRetreat()) {
		TaskPush(TASK_SEEKCOVER, TASKPRI_SEEKCOVER, -1, 5.0, false);
	}
}

/*
 * AimAtEnemy — Smooth aim toward target. From YaPB's aim system.
 */
void
yapbBot::AimAtEnemy(void)
{
	vector aimTarget;

	if (m_aimFlags & AIM_ENEMY && m_enemy != __NULL__) {
		/* aim at enemy with error based on difficulty */
		aimTarget = m_enemy.origin + m_enemy.view_ofs * 0.5;

		/* headshot chance based on difficulty */
		if (random() < m_diffData.headshotPct) {
			aimTarget = m_enemy.origin + m_enemy.view_ofs;
		}

		/* add aim error */
		float errorScale = m_diffData.aimError[0] +
			random() * (m_diffData.aimError[1] - m_diffData.aimError[0]);
		aimTarget[0] += crandom() * errorScale * 0.01;
		aimTarget[1] += crandom() * errorScale * 0.01;
	} else if (m_aimFlags & AIM_LASTENEMY && m_lastEnemy != __NULL__) {
		aimTarget = m_lastEnemyOrigin;
	} else {
		/* look at navigation target */
		aimTarget = m_destOrigin;
	}

	/* smooth aim — don't snap instantly */
	vector desiredAngles = vectoangles(aimTarget - (origin + view_ofs));

	/* normalize angles */
	if (desiredAngles[0] > 180.0) desiredAngles[0] -= 360.0;
	if (desiredAngles[1] > 180.0) desiredAngles[1] -= 360.0;

	/* aim speed based on difficulty (expert = instant, noob = slow) */
	float aimSpeed = 0.2 + (m_difficulty * 0.2);
	aimSpeed = bound(0.1, aimSpeed, 1.0);

	vector currentAngles = v_angle;
	if (currentAngles[0] > 180.0) currentAngles[0] -= 360.0;
	if (currentAngles[1] > 180.0) currentAngles[1] -= 360.0;

	/* interpolate */
	input_angles[0] = currentAngles[0] + (desiredAngles[0] - currentAngles[0]) * aimSpeed;
	input_angles[1] = currentAngles[1] + (desiredAngles[1] - currentAngles[1]) * aimSpeed;
	input_angles[2] = 0;
}

/*
 * FireWeapon — Press attack button when aimed at enemy.
 */
void
yapbBot::FireWeapon(void)
{
	if (m_enemy == __NULL__)
		return;

	if (time < m_shootTime)
		return;

	/* check if we're roughly aimed at the enemy */
	makevectors(v_angle);
	vector dir = normalize(m_enemy.origin - origin);
	float dot = dir * v_forward;

	/* accuracy threshold based on difficulty */
	float threshold = 0.85 + (m_difficulty * 0.03);

	if (dot >= threshold) {
		input_buttons |= INPUT_PRIMARY;
		m_shootTime = time + 0.1; /* basic fire rate limit */
	}
}

/*
 * SelectBestWeapon — Choose the best weapon for current situation.
 * Simplified from YaPB's complex weapon selection.
 */
void
yapbBot::SelectBestWeapon(void)
{
	/* TODO: port YaPB's full weapon preference system */
	/* For now, just use whatever we have */
}

/*
 * BuyStuff — Purchase weapons based on money and personality.
 * From YaPB's buy system in botlib.cpp.
 */
void
yapbBot::BuyStuff(void)
{
	/* TODO: port YaPB's full economy-aware buy system */
	/* For now, basic buying through console commands */
	if (m_money >= 3100) {
		localcmd(sprintf("cmd buy; cmd buyammo 0; cmd buyammo 1\n"));
	}
}

/*
 * ShouldRetreat — Decide if bot should fall back.
 */
bool
yapbBot::ShouldRetreat(void)
{
	if (health < 30 && m_personality != PERSONALITY_RUSHER)
		return true;
	if (health < 15)
		return true;
	return false;
}

/*
 * IsEnemyThreat — Assess if an enemy is a real threat.
 */
bool
yapbBot::IsEnemyThreat(entity ent)
{
	if (ent == __NULL__ || ent.health <= 0)
		return false;
	if (ent.team == this.team)
		return false;

	float dist = vlen(ent.origin - origin);
	if (dist > 2000.0)
		return false;

	return true;
}
