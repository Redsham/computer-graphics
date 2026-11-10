// =================
// === Constants ===
// =================

// --- Physics ---
#define TANK_ACCEL 1.0
#define TANK_MAX_SPEED 5.0

#define TANK_ANGULAR_ACCEL 1.0
#define TANK_MAX_ANGULAR_VELOCITY 1.0

#define TANK_FORWARD_DRAG 1.0
#define TANK_SIDE_DRAG 20.0

// --- Input ---
#define INPUT_FORWARD 87
#define INPUT_BACKWARD 83
#define INPUT_LEFT 65
#define INPUT_RIGHT 68


// ===============
// === Inputs ====
// ===============

float key(int k){
    return texelFetch(iChannel1, ivec2(k,0), 0).r;
}

vec2 getVelocity() {
    return texelFetch(iChannel0, ivec2(0,0), 0).xy;
}

float getRotation() {
    return texelFetch(iChannel0, ivec2(0,0), 0).z;
}

vec2 getPosition() {
    return texelFetch(iChannel0, ivec2(1, 0), 0).xy;
}


// ============
// === Main ===
// ============

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // --- Restore data ---
    vec2 velocity = getVelocity();
    float rotation = getRotation();

    float dt = iTimeDelta;
    
    /// --- Movement ---
    if(int(fragCoord.x) == 1) {
        vec2 position = getPosition();
        position += velocity * dt;
        fragColor = vec4(position, 0.0, 0.0);
        return;
    }

    // --- Input ---
    float forward  = key(INPUT_FORWARD) - key(INPUT_BACKWARD);
    float turn     = key(INPUT_RIGHT) - key(INPUT_LEFT);

    // --- Angular ---
    float angularVel = turn * TANK_ANGULAR_ACCEL;
    angularVel = clamp(angularVel, -TANK_MAX_ANGULAR_VELOCITY, TANK_MAX_ANGULAR_VELOCITY);

    rotation += angularVel * dt;

    // --- Acceleration ---
    vec2 forwardDir = vec2(cos(rotation), sin(rotation));
    vec2 accel = forwardDir * (forward * TANK_ACCEL);
    velocity += accel * dt;

    // --- Drag ---
    float vF = dot(velocity, forwardDir);
    float vS = dot(velocity, vec2(-forwardDir.y, forwardDir.x));
    vF *= exp(-TANK_FORWARD_DRAG * dt);
    vS *= exp(-TANK_SIDE_DRAG * dt);

    velocity = vF * forwardDir + vS * vec2(-forwardDir.y, forwardDir.x);

    // ======== Clamp speed ========
    float sp = length(velocity);
    if (sp > TANK_MAX_SPEED)
        velocity *= TANK_MAX_SPEED / sp;

    // --- Return ---
    fragColor = vec4(velocity, rotation, 0.0);
}
