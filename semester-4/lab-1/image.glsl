// --- Constants ---

const vec3  BACKGROUND_COLOR        = vec3(0.172, 0.243, 0.313);

const float GRAIN_TILE              = 256.0;
const float GRAIN_SIZE              = 100.0;

const float ROADLINE_RADIUS         = 0.005;
const float ROADLINE_SEGMENT_LENGTH = 0.025;
const float ROADLINE_SEGMENT_SPACE  = 0.1;
const vec3  ROADLINE_COLOR          = vec3(1.0);


const float CAR_WIDTH               = 0.03;
const float CAR_HEIGHT              = 0.06;
const vec3  CAR_COLOR               = vec3(0.9, 0.298, 0.235);
const float CAR_MAX_ANGLE           = 30.0;
const vec2  CAR_SHADOW_OFFSET       = vec2(0.015, -0.01);

const float CAR_WHEEL_WIDTH         = 0.005;
const float CAR_WHEEL_HEIGHT        = 0.01;
const float CAR_WHEEL_OFFSET_X      = CAR_WIDTH + CAR_WHEEL_WIDTH;
const float CAR_WHEEL_OFFSET_Y      = CAR_HEIGHT - CAR_WHEEL_HEIGHT - 0.01;

const float CAR_SHAKE_FREQUENCY = 20.0;
const float CAR_SHAKE_AMPLETUDE = 0.005;

const int   OBSTACLE_COUNT = 12;
const float OBSTACLE_SPEED = 0.5;
const float OBSTACLE_SIZE  = 0.05;
const float OBSTACLE_RESPAWN_TIME = 4.0;

// --- Noise ---

float hash( float n ) {
    return fract(sin(n) * 43758.5453123);
}

float noise1D( float x ) {
    float i = floor(x);
    float f = fract(x);

    float a = hash(i);
    float b = hash(i + 1.0);

    float u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float gridNoise2D(vec2 p) {
    return hash(floor(p));
}

// --- Math ---

vec2 rotate( in vec2 p, in float angle ) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(
        c * p.x - s * p.y,
        s * p.x + c * p.y
    );
}

// --- SDF Core Functions ---

float sdCircle( in vec2 p, in float r ) {
    return length(p) - r;
}

float sdBox( in vec2 p, in vec2 b ) {
    vec2 d = abs(p) - b;
    return length(max(d,0.0)) + min(max(d.x, d.y), 0.0);
}

float sdOrientedBox( vec2 p, vec2 b, float angle ) {
    vec2 local = rotate(p, -angle);
    return sdBox(local, b);
}

float sdSegment( in vec2 p, in vec2 a, in vec2 b )
{
    vec2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

float sdPentagram( in vec2 p, in float r )
{
    const float k1x = 0.809016994; // cos(π/ 5) = ¼(√5+1)
    const float k2x = 0.309016994; // sin(π/10) = ¼(√5-1)
    const float k1y = 0.587785252; // sin(π/ 5) = ¼√(10-2√5)
    const float k2y = 0.951056516; // cos(π/10) = ¼√(10+2√5)
    const float k1z = 0.726542528; // tan(π/ 5) = √(5-2√5)
    const vec2  v1  = vec2( k1x,-k1y);
    const vec2  v2  = vec2(-k1x,-k1y);
    const vec2  v3  = vec2( k2x,-k2y);
    
    p.x = abs(p.x);
    p -= 2.0*max(dot(v1,p),0.0)*v1;
    p -= 2.0*max(dot(v2,p),0.0)*v2;
    p.x = abs(p.x);
    p.y -= r;
    return length(p-v3*clamp(dot(p,v3),0.0,k1z*r)) * sign(p.y*v3.x-p.x*v3.y);
}

float sdTriangleIsosceles( in vec2 p, in vec2 q )
{
    p.x = abs(p.x);
    vec2 a = p - q*clamp( dot(p,q)/dot(q,q), 0.0, 1.0 );
    vec2 b = p - q*vec2( clamp( p.x/q.x, 0.0, 1.0 ), 1.0 );
    float s = -sign( q.y );
    vec2 d = min( vec2( dot(a,a), s*(p.x*q.y-p.y*q.x) ),
                  vec2( dot(b,b), s*(p.y-q.y)  ));
    return -sqrt(d.x)*sign(d.y);
}

// --- SDF Combined Functions ---
float sdCar( in vec2 p, in float angle ) {
    float body = sdOrientedBox(p, vec2(CAR_WIDTH, CAR_HEIGHT), angle);
        
    float wheel0 = sdOrientedBox(p + rotate(vec2(CAR_WHEEL_OFFSET_X,   CAR_WHEEL_OFFSET_Y), angle), vec2(CAR_WHEEL_WIDTH, CAR_WHEEL_HEIGHT), angle);
    float wheel1 = sdOrientedBox(p + rotate(vec2(-CAR_WHEEL_OFFSET_X,  CAR_WHEEL_OFFSET_Y), angle), vec2(CAR_WHEEL_WIDTH, CAR_WHEEL_HEIGHT), angle);
    float wheel2 = sdOrientedBox(p + rotate(vec2(CAR_WHEEL_OFFSET_X,  -CAR_WHEEL_OFFSET_Y), angle), vec2(CAR_WHEEL_WIDTH, CAR_WHEEL_HEIGHT), angle);
    float wheel3 = sdOrientedBox(p + rotate(vec2(-CAR_WHEEL_OFFSET_X, -CAR_WHEEL_OFFSET_Y), angle), vec2(CAR_WHEEL_WIDTH, CAR_WHEEL_HEIGHT), angle);
    float wheels_combined = min(min(wheel0, wheel1), min(wheel2, wheel3));
    
    return min(body, wheels_combined);
}

// --- Post-Processing ---
float vignette(vec2 fragCoord, vec2 resolution, float inner, float outer)
{
    vec2 uv = fragCoord / resolution;
    vec2 center = vec2(0.5, 0.5);          
    vec2 pos = uv - center;

    pos.x *= resolution.x / resolution.y;

    float radius = length(pos);
    return smoothstep(outer, inner, radius);
}
float grain(vec2 p, float world_position, float grainSize, float tileSize, float strength)
{
    vec2 coord = mod(p * grainSize + vec2(0.0, world_position * grainSize), tileSize);
    float n = gridNoise2D(coord);
    return mix(1.0 - strength, 1.0, n);
}

// --- Main ---

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Coordinates transformation
    vec2 p = (2.0*fragCoord-iResolution.xy)/iResolution.y;
    vec2 m = (2.0*iMouse.xy-iResolution.xy)/iResolution.y;
    
    // Physics
    float world_position   = texelFetch(iChannel2, ivec2(0, 0), 0).r;
    float car_velocity     = texelFetch(iChannel2, ivec2(0, 0), 0).g;
    float car_acceleration = texelFetch(iChannel2, ivec2(0, 0), 0).a;
    
    // Background
    vec3  color = BACKGROUND_COLOR * (abs(p.x) < 0.4 ? 0.8 : 1.0);
    
    // Roadline Drawing
    float cycle = ROADLINE_SEGMENT_LENGTH + ROADLINE_SEGMENT_SPACE;
    for (float y = -1.0; y <= 1.0; y += cycle) {
        float t = -fract(world_position / cycle) * cycle;
        float l = sdSegment(
            p,
            vec2(0.0, y - ROADLINE_SEGMENT_LENGTH * 0.5 + t),
            vec2(0.0, y + ROADLINE_SEGMENT_LENGTH * 0.5 + t)
        );

        float line = 1.0 - smoothstep(ROADLINE_RADIUS, ROADLINE_RADIUS + fwidth(l), l);
        color = mix(color, ROADLINE_COLOR, line);
    }
    
    // Car Drawing
    float position_x     = texelFetch(iChannel0, ivec2(0, 0), 0).r;
    float velocity_x     = texelFetch(iChannel1, ivec2(0, 0), 0).r;
    float car_rotation   = radians(-velocity_x * CAR_MAX_ANGLE);
    vec2  car_position   = vec2(position_x - p.x, -0.75 - p.y + car_acceleration * 5.0);
    vec2  car_shake      = vec2(noise1D(world_position * CAR_SHAKE_FREQUENCY), noise1D(world_position * CAR_SHAKE_FREQUENCY + 171.326)) * CAR_SHAKE_AMPLETUDE;
    
    float car            = sdCar(car_position + car_shake, car_rotation);
    float car_shadow     = sdCar(car_position + car_shake + CAR_SHADOW_OFFSET, car_rotation) + 0.07;
    
    if(car < 0.0)
        color = CAR_COLOR;
    else if(car_shadow < 0.1) {
        float shadow_strength = smoothstep(0.1, 0.0, car_shadow);
        color = mix(color, vec3(0.0), shadow_strength);
    }
        
    
    // Obstacles
    for (int i = 0; i < OBSTACLE_COUNT; i++) {
        float seed = float(i);
        float spawnOffset = hash(seed * 13.271) * OBSTACLE_RESPAWN_TIME;
        float local = mod(world_position + spawnOffset, OBSTACLE_RESPAWN_TIME);

        float y = 1.2 - local;
        float x = (hash(seed * 13.37) - 0.5) * 1.5 * 2.0;

        // Random shape
        float shapeType = hash(seed * 7.77);
        float d;
        
        if (shapeType < 0.25) {
        d = sdBox(p - vec2(x, y), vec2(0.05));
        } else if (shapeType < 0.5) {
            d = sdCircle(p - vec2(x, y), 0.05);
        } else if (shapeType < 0.75) {
            d = sdPentagram(p - vec2(x, y), 0.07);
        } else {
            d = sdTriangleIsosceles(p - vec2(x,y), vec2(0.05, -0.2));
        }
        

        if (d < 0.0) {
            color = vec3(0.2, 0.8, 0.3);
        }
    }
    
    // Post-Processing
    color *= vignette(fragCoord, iResolution.xy, 0.5, 1.5);
    color *= grain(p, world_position, GRAIN_SIZE, GRAIN_TILE, 0.01);
    
    fragColor = vec4(color, 1.0);
}

