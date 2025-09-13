// World offset buffer

const float MIN_VELOCITY        = 1.25;
const float MAX_VELOCITY        = 2.0;

const float ACCELERATION        = 2.0;
const float DEACCELERATION      = 1.0;

const float VELOCITY_RESPONSE   = 5.0;
const float ACCELERATION_SMOOTH = 15.0;

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float world_position          = texelFetch(iChannel0, ivec2(0,0), 0).r;
    float last_velocity       = clamp(texelFetch(iChannel0, ivec2(0,0), 0).g, MIN_VELOCITY, MAX_VELOCITY);
    float horizontal_velocity = abs(texelFetch(iChannel1, ivec2(0,0), 0).r);
    float last_smooth_acceleration = texelFetch(iChannel0, ivec2(0,0), 0).a;
    
    float target_velocity  = mix(MAX_VELOCITY, MIN_VELOCITY, horizontal_velocity);
    bool  is_acceleration  = target_velocity >= last_velocity;
    float mix_speed        = is_acceleration ? ACCELERATION : DEACCELERATION;
    float current_velocity = target_velocity - (target_velocity - last_velocity) * exp(-iTimeDelta * mix_speed * VELOCITY_RESPONSE);

    
    world_position += iTimeDelta * current_velocity;
    float acceleration = current_velocity - last_velocity;
    float smooth_acceleration = mix(last_smooth_acceleration, acceleration, 1.0 - exp(-iTimeDelta * ACCELERATION_SMOOTH));
    
    fragColor = vec4(world_position, current_velocity, acceleration, smooth_acceleration);
}
