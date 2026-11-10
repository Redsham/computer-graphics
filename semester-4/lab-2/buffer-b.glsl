// =================
// === Constants ===
// =================

#define BULLET_SPEED        30.0
#define BULLET_RADIUS        0.05
#define BULLET_LIFETIME      1.5
#define BULLET_SUBSTEPS        8

#define GRAVITY  vec3(0.0, -9.8, 0.0)

#define IMPACT_SPEED         1.2
#define IMPACT_MAX_RADIUS    1.2

#define MUZZLE_BASE          vec3(0.30, 0.62, 0.00)
#define MUZZLE_OFFSET        vec3(1.70, 0.10, 0.00)

#define KEY_SPACE 32

float key(int k){ 
    return texelFetch(iChannel1, ivec2(k,0), 0).r; 
}

vec4 S(int x){ 
    return texelFetch(iChannel2, ivec2(x,0), 0); 
}

vec4 Ang(){ 
    return texelFetch(iChannel0, ivec2(0,0), 0); 
}


// ============
// === Math ===
// ============

float deg(float d){ return d * 0.0174532925; }

mat3 rotY(float a){ 
    float c = cos(a), s = sin(a); 
    return mat3(c,0,s, 0,1,0, -s,0,c); 
}

mat3 rotZ(float a){ 
    float c = cos(a), s = sin(a); 
    return mat3(c,-s,0, s,c,0, 0,0,1); 
}


// ===========
// === SDF ===
// ===========

float sdPlane(vec3 p){ return p.y; }

float sdBox(vec3 p, vec3 b){
    vec3 d = abs(p) - b;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float map(vec3 p){
    float d = sdPlane(p);

    d = min(d, sdBox(p - vec3(0.0,0.4,0.0), vec3(1.3*0.8,0.2,1.2*0.5 - 0.05*2.0)));
    d = min(d, sdBox(p - vec3(0.0,0.45,-1.2*0.5), vec3(1.3,0.1,0.05*4.0)));
    d = min(d, sdBox(p - vec3(0.0,0.45, 1.2*0.5), vec3(1.3,0.1,0.05*4.0)));

    float a = deg(160.0);
    mat3 R = rotY(a);
    vec3 q = transpose(R) * (p - vec3(3.0,0.0,3.0));
    d = min(d, sdBox(q - vec3(0.0,0.4,0.0), vec3(1.3*0.8,0.2,1.2*0.5 - 0.05*2.0)));

    return d;
}


// =================
// === Utilities ===
// =================

void getMuzzle(out vec3 pos, out vec3 dir)
{
    vec2 t = Ang().xy;
    mat3 Ry = rotY(deg(-t.x));
    mat3 Rz = rotZ(deg(-t.y));

    pos = MUZZLE_BASE + Ry * (Rz * MUZZLE_OFFSET);
    dir = normalize(Ry * (Rz * vec3(1.0, 0.0, 0.0)));
}


// ============
// === Main ===
// ============

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec4 P = S(0);   // Bullet position + lifetime
    vec4 V = S(1);   // Bullet velocity + state
    vec4 I = S(2);   // Impact point + impact time
    
    float dt = max(iTimeDelta, 1e-4);

    // --- Init ---
    if (iFrame == 0) {
        P = vec4(0);
        V = vec4(0);
        I = vec4(0);
    }

    // --- Fire ---
    vec3 muzzle, dir;
    getMuzzle(muzzle, dir);

    if (key(KEY_SPACE) > 0.5 && V.w == 0.0)
    {
        P = vec4(muzzle, BULLET_LIFETIME);
        V = vec4(dir * BULLET_SPEED, 1.0);
        I = vec4(0.0);
    }

    // --- Physics ---
    if (V.w == 1.0)
    {
        vec3 pos = P.xyz;
        vec3 vel = V.xyz;

        float h = dt / float(BULLET_SUBSTEPS);

        for (int i = 0; i < BULLET_SUBSTEPS; i++)
        {
            vel += GRAVITY * h;
            pos += vel * h;

            float d = map(pos) - BULLET_RADIUS;
            if (d < 0.0)
            {
                V.w = 2.0;       // hit
                P.w = 0.0;
                I = vec4(pos, iTime);
                break;
            }

            P.w -= h;
            if (P.w <= 0.0)
            {
                V.w = 0.0;
                break;
            }
        }

        P.xyz = pos;
        V.xyz = vel;
    }

    // --- Impact End ---
    if (V.w == 2.0)
    {
        float r = (iTime - I.w) * IMPACT_SPEED;
        if (r > IMPACT_MAX_RADIUS)
        {
            V = vec4(0.0);
            P = vec4(0.0);
            I = vec4(0.0);
        }
    }

    // --- Output ---
    ivec2 uv = ivec2(fragCoord);

    if      (uv.x == 0) fragColor = P;
    else if (uv.x == 1) fragColor = V;
    else if (uv.x == 2) fragColor = I;
    else fragColor = vec4(0.0);
}
