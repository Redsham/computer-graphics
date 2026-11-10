// =================
// === Constants ===
// =================

#define TANK_BODY_WIDTH 1.2
#define TANK_BODY_LENGTH 1.3
#define TANK_TRACK_WIDTH 0.05

// ============
// === MATH ===
// ============

float deg(float d) { return d * 0.017453292519943295; }
float rad(float r) { return r * 57.29577951308232; }    

mat3 rotX(float a){ float c=cos(a), s=sin(a); return mat3(1,0,0,  0,c,-s,  0,s,c); }
mat3 rotY(float a){ float c=cos(a), s=sin(a); return mat3(c,0,s,  0,1,0,  -s,0,c); }
mat3 rotZ(float a){ float c=cos(a), s=sin(a); return mat3(c,-s,0, s,c,0, 0,0,1); }

vec3 toLocal(vec3 p, vec3 pivot, mat3 R) { return transpose(R) * (p - pivot); }

// ===========
// === SDF ===
// ===========

vec4 opElongate(in vec3 p, in vec3 h) { vec3 q = abs(p)-h; return vec4( max(q,0.0), min(max(q.x,max(q.y,q.z)),0.0) ); }

float sdTriIso2D(vec2 p, float base, float height)
{
    vec2 q = vec2(0.5*base, height);
    p.x = abs(p.x);
    vec2 a = p - q * clamp(dot(p,q)/dot(q,q), 0.0, 1.0);
    vec2 b = p - q * vec2(clamp(p.x/q.x, 0.0, 1.0), 1.0);
    float s = -sign(q.y);
    vec2 d = min(vec2(dot(a,a), s*(p.x*q.y - p.y*q.x)),
                 vec2(dot(b,b), s*(p.y - q.y)));
    return -sqrt(d.x) * sign(d.y);
}

float sdPlane(vec3 p) { return p.y; }
float sdBox(vec3 p, vec3 b) { vec3 d = abs(p) - b; return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0)); }
float sdEllipsoid( in vec3 p, in vec3 r ) { float k0 = length(p/r); float k1 = length(p/(r*r)); return k0*(k0-1.0)/k1; }
float sdTriPrism( vec3 p, vec2 h ) { vec3 q = abs(p); return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5); }
float sdTriPrism2(vec3 p, float base, float height, float halfT) { vec2 q = vec2(p.x, -p.y); float d2 = sdTriIso2D(q, base, height); float dy = abs(p.z) - halfT; return max(d2, dy); }
float sdCappedCylinder( vec3 p, float r, float h ) { vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(r,h); return min(max(d.x,d.y),0.0) + length(max(d,0.0)); }

float sdCappedCone( vec3 p, vec3 a, vec3 b, float ra, float rb )
{
  float rba  = rb-ra; float baba = dot(b-a,b-a); float papa = dot(p-a,p-a); float paba = dot(p-a,b-a)/baba; float x = sqrt( papa - paba*paba*baba ); float cax = max(0.0,x-((paba<0.5)?ra:rb)); float cay = abs(paba-0.5)-0.5;
  float k = rba*rba + baba; float f = clamp( (rba*(x-ra)+paba*baba)/k, 0.0, 1.0 ); float cbx = x-ra - f*rba; float cby = paba - f; float s = (cbx<0.0 && cay<0.0) ? -1.0 : 1.0; return s*sqrt( min(cax*cax + cay*cay*baba, cbx*cbx + cby*cby*baba) );
}

// --- Custom SDF ---
float sdBody(in vec3 p)
{
    float d = 1.0;
    d = min(d, sdBox(p - vec3(0.0, 0.4, 0.0), vec3(TANK_BODY_LENGTH * 0.8, 0.2, TANK_BODY_WIDTH / 2.0 - TANK_TRACK_WIDTH * 2.0)));
    d = min(d, sdTriPrism2(p - vec3(-TANK_BODY_LENGTH * 0.8, 0.6, 0.0), TANK_BODY_LENGTH * 0.4, 0.2, TANK_BODY_WIDTH / 2.0 - TANK_TRACK_WIDTH * 2.0));
    d = min(d, sdTriPrism2(p - vec3(TANK_BODY_LENGTH * 0.8, 0.6, 0.0), TANK_BODY_LENGTH * 0.5, 0.2, TANK_BODY_WIDTH / 2.0 - TANK_TRACK_WIDTH * 2.0));    
    d = min(d, sdBox(p - vec3(0.0, 0.45, -TANK_BODY_WIDTH / 2.0), vec3(TANK_BODY_LENGTH, 0.1, TANK_TRACK_WIDTH * 4.0)));
    d = min(d, sdTriPrism2(p - vec3(-TANK_BODY_LENGTH, 0.55, -TANK_BODY_WIDTH / 2.0), 0.2, 0.2, TANK_TRACK_WIDTH * 4.0));
    d = min(d, sdTriPrism2(p - vec3(TANK_BODY_LENGTH, 0.55, -TANK_BODY_WIDTH / 2.0), 0.2, 0.2, TANK_TRACK_WIDTH * 4.0));
    d = min(d, sdBox(p - vec3(0.0, 0.45, TANK_BODY_WIDTH / 2.0), vec3(TANK_BODY_LENGTH, 0.1, TANK_TRACK_WIDTH * 4.0)));
    d = min(d, sdTriPrism2(p - vec3(-TANK_BODY_LENGTH, 0.55, TANK_BODY_WIDTH / 2.0), 0.2, 0.2, TANK_TRACK_WIDTH * 4.0));
    d = min(d, sdTriPrism2(p - vec3(TANK_BODY_LENGTH, 0.55, TANK_BODY_WIDTH / 2.0), 0.2, 0.2, TANK_TRACK_WIDTH * 4.0));
    d = min(d, sdCappedCylinder(toLocal(p, vec3(-TANK_BODY_LENGTH * 0.8 - 0.1, 0.63, -TANK_BODY_WIDTH / 3.5), rotX(deg(90.0))), 0.17, 0.02));
    d = min(d, sdCappedCylinder(toLocal(p, vec3(-TANK_BODY_LENGTH * 0.8 - 0.1, 0.63, TANK_BODY_WIDTH / 3.5), rotX(deg(90.0))), 0.17, 0.02));
    d = min(d, sdBox(p - vec3(TANK_BODY_LENGTH - 0.15, 0.55, TANK_BODY_WIDTH / 5.0), vec3(0.07, 0.05, 0.12)));
    return d;
}
float sdDetails(in vec3 p) 
{
    float d = 1.0;
    { vec3 h = vec3(TANK_BODY_LENGTH / 2.0 + 0.35, 0.0, 0.1);
      vec4 w = opElongate(p - vec3(0.0, 0.25, -TANK_BODY_WIDTH / 2.0), h);
      float core = sdEllipsoid(w.xyz, vec3(0.35, 0.25, TANK_TRACK_WIDTH));
      d = min(d, core + w.w); }
    { vec3 h = vec3(TANK_BODY_LENGTH / 2.0 + 0.35, 0.0, 0.1);
      vec4 w = opElongate(p - vec3(0.0, 0.25, TANK_BODY_WIDTH / 2.0), h);
      float core = sdEllipsoid(w.xyz, vec3(0.35, 0.25, TANK_TRACK_WIDTH));
      d = min(d, core + w.w); }
    d = min(d, sdCappedCylinder(toLocal(p, vec3(-TANK_BODY_LENGTH * 0.8 - 0.1, 0.63, 0.0), rotX(deg(90.0))), 0.15, TANK_BODY_WIDTH / 2.0 - TANK_TRACK_WIDTH * 2.0 - 0.05));
    return d;
}
float sdTurret(in vec3 p, in vec2 t)
{
    float d = 1.0;
    vec3 hP = toLocal(p, vec3(0.3, 0.62, 0.0), rotY(deg(-t.x)));
    vec3 vP = toLocal(hP, vec3(0.35, 0.0, 0.0), rotZ(deg(-t.y)));
    d = min(d, sdCappedCone(hP, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.22, 0.0), 0.45, 0.35));
    d = min(d, sdCappedCone(hP, vec3(0.0, 0.22, 0.1), vec3(0.0, 0.27, 0.1), 0.15, 0.14));
    d = min(d, sdCappedCone(hP, vec3(0.35, 0.1, -0.2), vec3(0.35, 0.1, 0.2), 0.1, 0.1));
    d = min(d, sdCappedCone(vP, vec3(0.0, 0.1, 0.0), vec3(0.25, 0.1, 0.0), 0.1, 0.08));
    d = min(d, sdCappedCone(vP, vec3(0.15, 0.1, 0.0), vec3(1.5, 0.1, 0.0), 0.05, 0.03));
    return d;
}

// --- Complex SDF ---
vec2 sdTank(in vec3 p, in vec2 t)
{
    vec2 res = vec2(1.0, 0.0);
    float dBody = sdBody(p);
    float dDetails = sdDetails(p);
    float dTurret = sdTurret(p, t);
    if(dBody < dDetails || dTurret < dDetails) res = vec2(min(dTurret, dBody), 1.0);
    else res = vec2(dDetails, 2.0);
    return res;
}

vec2 sRes(in vec2 a, in vec2 b) { return a.x < b.x ? a : b; }

// --- Bullet state (Buffer A) ---
vec4 BULLET_P(){ return texelFetch(iChannel1, ivec2(0,0), 0); }
vec4 BULLET_V(){ return texelFetch(iChannel1, ivec2(1,0), 0); }
vec4 IMPACT() { return texelFetch(iChannel1, ivec2(2,0), 0); }
vec4 FLASH()  { return texelFetch(iChannel1, ivec2(3,0), 0); }

// --- Scene ---
vec2 map(in vec3 p) {
    vec2 res = vec2(sdPlane(p), 0.0);
    res = sRes(res, sdTank(toLocal(p, vec3(0.0, 0.0, 0.0), rotY(deg(0.0))), texelFetch(iChannel0, ivec2(0,0), 0).xy));
    res = sRes(res, sdTank(toLocal(p, vec3(3.0, 0.0, 3.0), rotY(deg(160.0))), vec2(0.0)));

    vec4 P = BULLET_P(), V = BULLET_V();
    if(V.w==1.0 && P.w>0.0){
        float dB = length(p - P.xyz) - 0.05;
        res = sRes(res, vec2(dB, 3.0));
    }
    if(V.w==2.0){
        vec4 I = IMPACT();
        float r = (iTime - I.w) * 1.2;
        if(r < 1.2){
            float dW = abs(length(p - I.xyz) - r) - 0.01;
            res = sRes(res, vec2(dW, 4.0));
        }
    }
    return res;
}

vec3 calcNormal(in vec3 p) {
    float e = 0.0005; vec2 h = vec2(1.0, -1.0);
    return normalize(
        h.xyy * map(p + h.xyy * e).x +
        h.yyx * map(p + h.yyx * e).x +
        h.yxy * map(p + h.yxy * e).x +
        h.xxx * map(p + h.xxx * e).x
    );
}

// =====================
// === Math & Render ===
// =====================

float raymarch(vec3 ro, vec3 rd, out float matId, out vec3 hitPos, out vec3 hitNor, float tMax) {
    float t = 0.0;
    for (int i = 0; i < 1000; i++) {
        vec2 h = map(ro + rd * t);
        if (h.x < 0.001) {
            matId = h.y;
            hitPos = ro + rd * t;
            hitNor = (matId < 0.5) ? vec3(0,1,0) : calcNormal(hitPos);
            return t;
        }
        t += h.x;
        if (t > tMax) break;
    }
    matId = -1.0;
    return -1.0;
}

float softShadow(vec3 ro, vec3 rd, float mint, float maxt) {
    float res = 1.0, t = mint;
    for (int i = 0; i < 24; i++) {
        float h = map(ro + rd * t).x;
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.01, 0.2);
        if (t > maxt) break;
    }
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

float calcAO(vec3 p, vec3 n) {
    float occ = 0.0, sca = 1.0;
    for (int i = 0; i < 0; i++) {
        float h = 0.02 + 0.08 * float(i);
        float d = map(p + n * h).x;
        occ += (h - d) * sca;
        sca *= 0.7;
    }
    return clamp(1.0 - 2.0 * occ, 0.0, 1.0);
}

float checker(vec2 p) {
    vec2 q = floor(p);
    return mod(q.x + q.y, 2.0);
}

vec3 baseSky(vec3 rd) {
    float t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    return mix(vec3(0.55,0.65,0.85), vec3(0.20,0.45,0.90), t);
}

float fogTransmittance(vec3 ro, vec3 rd, float t, float density, float invH) {
    float k = rd.y * invH, y0 = ro.y * invH;
    if (abs(k) < 1e-4) { float od = density * t * exp(-y0); return exp(-od); }
    float od = density * exp(-y0) * (1.0 - exp(-k * t)) / k;
    return exp(-od);
}

mat3 setCamera(vec3 ro, vec3 ta) {
    vec3 f = normalize(ta - ro);
    vec3 r = normalize(cross(vec3(0,1,0), f));
    vec3 u = cross(f, r);
    return mat3(r, u, f);
}

// --- Emissive + surfaces ---
vec3 shade(vec3 ro, vec3 rd, float t, float matId, vec3 p, vec3 n) {
    if (matId > 2.5) {
        if (matId < 3.5) {
            float glow = smoothstep(0.12, 0.0, abs(length(p - BULLET_P().xyz) - 0.05));
            return vec3(3.0, 2.5, 1.0) * glow;
        } else {
            float r = (iTime - IMPACT().w) * 1.2;
            float edge = smoothstep(0.03, 0.0, abs(length(p - IMPACT().xyz) - r));
            return vec3(2.5, 1.2, 0.4) * edge;
        }
    }
    vec3 l = normalize(vec3(-0.5, 0.8, -0.3));
    vec3 h = normalize(l - rd);
    vec3 albedo = (matId < 0.5)
        ? mix(vec3(0.08), vec3(0.18), checker(p.xz * 2.0))
        : ((matId < 1.5) ? vec3(0.19, 0.33, 0.18) : vec3(0.09, 0.09, 0.09));
        
    float ao   = calcAO(p, n);
    float diff = max(dot(n, l), 0.0);
    float sh   = softShadow(p + n * 0.01, l, 0.02, 4.0);
    float spe  = pow(max(dot(n, h), 0.0), 32.0);
    
    vec3 sun  = (albedo * diff * sh + 0.5 * spe * sh) * vec3(1.2, 1.1, 0.9);
    vec3 skyA = albedo * ao * 0.5 * baseSky(rd);
    vec3 back = albedo * 0.2 * max(dot(n, normalize(vec3(0.5,0.0,0.6))), 0.0);
    
    return sun + skyA + back;
}

// --- Muzzle flash ---
vec3 flash(vec3 ro, vec3 rd){
    vec4 f = FLASH(); if(f.x<=0.0) return vec3(0.0);
    vec2 t = texelFetch(iChannel0, ivec2(0,0), 0).xy;
    mat3 Ry = rotY(deg(-t.x)), Rz = rotZ(deg(-t.y));
    
    vec3 base = vec3(0.3, 0.62, 0.0);
    vec3 mpos = base + Ry*(Rz*vec3(1.50,0.10,0.0));
    vec3 mdir = normalize(Ry*(Rz*vec3(1.0,0.0,0.0)));
    float onAxis = smoothstep(cos(0.25), 1.0, dot(rd, mdir));
    
    float tHit = dot(mpos - ro, rd);
    float fall = exp(-max(tHit,0.0)*0.8);
    float timeFade = f.x/0.07;
    return vec3(3.0,2.2,1.0) * onAxis * fall * timeFade;
}


// --- Render ---
vec3 render(vec3 ro, vec3 rd) {
    const float tMax = 60.0;
    const float fogDensity = 0.1;
    const float invH = 1.0;

    float matId; vec3 p, n;
    float t = raymarch(ro, rd, matId, p, n, tMax);
    if (t < 0.0) {
        vec3 bg = baseSky(rd);
        float trans = fogTransmittance(ro, rd, tMax, fogDensity, invH);
        return mix(bg, bg, trans);
    }
    vec3 col = shade(ro, rd, t, matId, p, n);
    vec3 fogCol = baseSky(rd);
    float trans = fogTransmittance(ro, rd, t, fogDensity, invH);
    return mix(fogCol, col, trans);
}

void orbitCamera(in vec2 fragCoord, in vec2 res, in vec4 mouse,
                 in vec3 ta, in float radius, in float focal,
                 out vec3 ro, out vec3 rd)
{
    vec2 p  = (2.0*fragCoord - res) / res.y;
    vec2 m  = (mouse.xy == vec2(0.0)) ? 0.5*res : mouse.xy;
    vec2 mu = m / res;
    float yaw   = (mu.x*2.0 - 1.0) * 3.14159265;
    float pitch = clamp((0.5 - mu.y) * 1.8, -1.2, 1.2);
    vec3 dir = normalize(vec3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch)));
    ro = ta - dir * radius;
    mat3 cam = setCamera(ro, ta);
    rd = normalize(cam * vec3(p, focal));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 ro, rd;
    orbitCamera(fragCoord, iResolution.xy, iMouse, vec3(0.0, 0.5, 0.0), 5.0, 2.2, ro, rd);
    vec3 col = render(ro, rd) + flash(ro, rd);
    col = pow(clamp(col,0.0,1.0), vec3(0.4545));
    fragColor = vec4(col,1.0);
}
