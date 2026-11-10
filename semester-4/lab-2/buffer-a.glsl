// =================
// === Constants ===
// =================

#define YAW_MAX_SPEED    120.0
#define PITCH_MAX_SPEED   90.0
#define YAW_ACCEL        360.0
#define PITCH_ACCEL      240.0
#define LIN_FRICTION       2.5
#define QUAD_DRAG          0.02
#define BRAKE_EXTRA        3.0
#define INPUT_CURVE        1.6

#define KEY_LEFT  37
#define KEY_UP    38
#define KEY_RIGHT 39
#define KEY_DOWN  40

#define LIMIT_DOWN -10.0
#define LIMIT_UP    15.0

#define RESTITUTION 0.35
#define WALL_DAMP   6.0
#define STOP_SPEED  1.5

// ============
// === Main ===
// ============

float key(in int k) { return texelFetch(iChannel0, ivec2(k,  0), 0).r; }

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    float left  = key(KEY_LEFT);
    float right = key(KEY_RIGHT);
    float up    = key(KEY_UP);
    float down  = key(KEY_DOWN);

    vec4 state = texelFetch(iChannel1, ivec2(0,0), 0);
    vec2 rot = state.xy;
    vec2 vel = state.zw;

    if (iFrame == 0) { rot = vec2(0); vel = vec2(0); }

    float dt = max(iTimeDelta, 1e-4);
    vec2 raw = vec2(right - left, up - down);
    vec2 u = sign(raw) * pow(abs(raw), vec2(INPUT_CURVE));

    vec2 accel = vec2(YAW_ACCEL, PITCH_ACCEL) * u;
    vel += accel * dt;
    vel *= exp(-LIN_FRICTION * dt);
    vel -= vel * abs(vel) * QUAD_DRAG * dt;

    vec2 oppose = step(0.0, -(u * vel));
    vel *= 1.0 - oppose * clamp(BRAKE_EXTRA * dt, 0.0, 0.95);

    vec2 vmax = vec2(YAW_MAX_SPEED, PITCH_MAX_SPEED);
    vel = clamp(vel, -vmax, vmax);

    rot += vel * dt;

    if (rot.y > LIMIT_UP) {
        rot.y = LIMIT_UP;
        if (vel.y > 0.0) vel.y = -vel.y * RESTITUTION;
        vel.y *= max(0.0, 1.0 - WALL_DAMP * dt);
        if (abs(vel.y) < STOP_SPEED) vel.y = 0.0;
    }
    if (rot.y < LIMIT_DOWN) {
        rot.y = LIMIT_DOWN;
        if (vel.y < 0.0) vel.y = -vel.y * RESTITUTION;
        vel.y *= max(0.0, 1.0 - WALL_DAMP * dt);
        if (abs(vel.y) < STOP_SPEED) vel.y = 0.0;
    }

    rot.x = mod(rot.x + 180.0, 360.0) - 180.0;

    fragColor = vec4(rot, vel);
}
