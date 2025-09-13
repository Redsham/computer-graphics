// Input & Acceleration buffer

const int KEY_LEFT  = 37;
const int KEY_RIGHT = 39;

const float PHYSICS_MAX_VELOCITY = 1.0;
const float PHYSICS_ACCELERATION = 5.0;
const float PHYSICS_FRICTION = 0.95;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 vel = texelFetch(iChannel0, ivec2(0,0), 0).xy;

    // Input
    float left  = texelFetch(iChannel1, ivec2(KEY_LEFT, 0), 0).r;
    float right = texelFetch(iChannel1, ivec2(KEY_RIGHT,0), 0).r;

    vec2 acc = vec2(right - left, 0.0) * PHYSICS_ACCELERATION;

    // Acceleration
    vel += acc * iTimeDelta;

    // Friction
    vel *= pow(PHYSICS_FRICTION, iTimeDelta * 60.0);
    
    // Velocity limit
    float speed = length(vel);
    if(speed > 0.0)
        vel = normalize(vel) * clamp(speed, 0.0, PHYSICS_MAX_VELOCITY);

    fragColor = vec4(vel, 0.0, 1.0);
}

