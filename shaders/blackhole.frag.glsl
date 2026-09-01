#version 300 es
precision highp float;

uniform float u_time;
uniform float u_formationTime;
uniform float u_bhMass;
uniform float u_diskRadius;
uniform float u_diskThickness;
uniform float u_diskDensity;
uniform float u_diskTurbulence;
uniform float u_diskRotation;
uniform float u_temperature;
uniform float u_dopplerStrength;
uniform float u_redshiftStrength;
uniform float u_lensingStrength;
uniform float u_starDensity;
uniform float u_starBrightness;
uniform float u_milkyWayIntensity;
uniform float u_bloomStrength;
uniform float u_exposure;
uniform float u_vignette;
uniform float u_filmGrain;
uniform float u_chromaticAberration;
uniform int u_rayIterations;
uniform int u_debugMode;
uniform float u_cameraDistance;
uniform float u_cameraTheta;
uniform float u_cameraPhi;
uniform vec2 u_resolution;
uniform float u_screenshotMode;
uniform float u_seed;

in vec2 vUv;
out vec4 fragColor;

#define PI 3.14159265359
#define TAU 6.28318530718
#define MAX_STEPS 128
#define DISK_INNER 2.5
#define DISK_OUTER 8.0
#define EVENT_HORIZON 2.0

// --- Noise functions ---
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float hash3(vec3 p) {
    return hash(p.xy + p.z * 31.7);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
            mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
            mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y),
        f.z
    );
}

float fbm3(vec3 p, int octaves) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        if (i >= octaves) break;
        v += a * noise3(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// --- Camera ---
mat3 lookAtMatrix(vec3 eye, vec3 target, vec3 up) {
    vec3 f = normalize(target - eye);
    vec3 r = normalize(cross(f, up));
    vec3 u = cross(r, f);
    return mat3(r, u, f);
}

mat3 rotationY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c, 0, s, 0, 1, 0, -s, 0, c);
}

mat3 rotationX(float a) {
    float c = cos(a), s = sin(a);
    return mat3(1, 0, 0, 0, c, -s, 0, s, c);
}

// --- Accretion Disk ---
vec3 diskColor(float r, float phi, float turbSeed) {
    float t = (r - DISK_INNER) / (DISK_OUTER - DISK_INNER);
    
    // Radial density profile
    float density = exp(-t * 3.0) * (1.0 - smoothstep(0.0, 0.05, abs(t - 0.5)));
    
    // Turbulence
    float turb = fbm(vec2(phi * 3.0 + u_time * u_diskRotation, r * 2.0 + turbSeed), 4);
    turb = mix(0.5, turb, u_diskTurbulence);
    
    // Temperature gradient (hotter near center)
    float temp = 1.0 - t * 0.7;
    temp *= u_temperature;
    
    // Color from temperature
    vec3 hot = vec3(1.0, 0.95, 0.8);
    vec3 warm = vec3(1.0, 0.5, 0.1);
    vec3 cool = vec3(0.8, 0.2, 0.05);
    vec3 col = mix(cool, warm, smoothstep(0.0, 0.5, temp));
    col = mix(col, hot, smoothstep(0.5, 1.0, temp));
    
    return col * density * turb * u_diskDensity * 8.0;
}

// --- Starfield ---
vec3 starfield(vec3 dir, float seed) {
    // Simple hash-based starfield
    vec3 p = dir * 200.0;
    vec3 fp = floor(p);
    vec3 frac_p = fract(p) - 0.5;
    
    float d = length(frac_p);
    float h = hash3(fp + seed);
    
    if (h > 0.997 && d < 0.1) {
        float brightness = (h - 0.997) / 0.003 * u_starBrightness;
        float twinkle = 0.8 + 0.2 * sin(u_time * (1.0 + h * 5.0));
        
        // Star color variation
        vec3 starCol = vec3(0.8 + 0.2 * h, 0.8 + 0.1 * hash3(fp * 1.3 + seed), 0.9 + 0.1 * hash3(fp * 2.7 + seed));
        return starCol * brightness * twinkle * 3.0;
    }
    return vec3(0.0);
}

// --- Milky Way ---
vec3 milkyWay(vec3 dir) {
    float stripe = dot(dir, vec3(0.0, 1.0, 0.3));
    stripe = smoothstep(-0.2, 0.2, stripe);
    
    float detail = fbm(vec2(atan(dir.x, dir.z) * 3.0, dir.y * 5.0 + 10.0), 5);
    float dust = fbm(vec2(atan(dir.x, dir.z) * 2.0, dir.y * 4.0 + 5.0), 3);
    
    vec3 milkyCol = vec3(0.4, 0.45, 0.55) * stripe * detail * 0.3;
    milkyCol += vec3(0.3, 0.2, 0.15) * dust * stripe * 0.15;
    
    return milkyCol * u_milkyWayIntensity;
}

// --- Schwarzschild Geodesic Integration ---
void traceRay(vec3 ro, vec3 rd, out vec3 color, out float closestR, out int crossings) {
    color = vec3(0.0);
    closestR = 1e10;
    crossings = 0;
    
    float M = u_bhMass;
    vec3 bhPos = vec3(0.0);
    
    // Transform ray into orbital plane
    vec3 toBH = bhPos - ro;
    float distToBH = length(toBH);
    
    // Impact parameter
    vec3 vel = rd;
    vec3 L = cross(toBH, vel);
    float L_len = length(L);
    float b = L_len; // impact parameter
    
    // Initial conditions in polar-like coords
    vec3 n = normalize(toBH);
    vec3 u_vec = normalize(cross(L, n));
    
    // Start integration from camera
    float r = distToBH;
    float phi = 0.0;
    
    vec2 diskUV = vec2(0.0);
    vec3 accumulatedDisk = vec3(0.0);
    float accumulatedOpacity = 0.0;
    bool hitHorizon = false;
    
    float stepSize = 0.15;
    
    vec3 currentPos = ro;
    vec3 currentDir = rd;
    
    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= u_rayIterations) break;
        
        vec3 toCenter = bhPos - currentPos;
        r = length(toCenter);
        
        if (r < closestR) closestR = r;
        
        // Event horizon check
        if (r < EVENT_HORIZON * M) {
            hitHorizon = true;
            break;
        }
        
        // Accretion disk crossing
        if (abs(currentPos.y) < u_diskThickness * 0.5) {
            float diskR = length(vec2(currentPos.x, currentPos.z));
            if (diskR > DISK_INNER * M && diskR < DISK_OUTER * M) {
                vec3 diskCol = diskColor(diskR / M, atan(currentPos.z, currentPos.x), hash(currentPos.xz * 0.1));
                
                // Doppler beaming
                vec3 diskVelocity = normalize(cross(vec3(0, 1, 0), vec3(currentPos.x, 0, currentPos.z)));
                float doppler = dot(currentDir, diskVelocity);
                float dopplerFactor = pow(1.0 + doppler * u_dopplerStrength, 3.0);
                diskCol *= dopplerFactor;
                
                // Gravitational redshift
                float gravRedshift = 1.0 / sqrt(max(1.0 - 2.0 * M / r, 0.01));
                gravRedshift = mix(1.0, gravRedshift, u_redshiftStrength);
                
                accumulatedDisk += diskCol * gravRedshift * stepSize * 0.5;
                crossings++;
            }
        }
        
        // Gravitational deflection (simplified Schwarzschild-like)
        float g = u_lensingStrength * M / (r * r + 0.01);
        vec3 toCenterNorm = normalize(toCenter);
        
        // Apply deflection perpendicular to radial direction and velocity
        vec3 deflection = cross(currentDir, cross(toCenterNorm, currentDir));
        currentDir += deflection * g * stepSize;
        currentDir = normalize(currentDir);
        
        // Step forward
        currentPos += currentDir * stepSize;
        phi += stepSize / max(r, 0.1);
        
        // Adaptive step size
        stepSize = mix(0.05, 0.4, smoothstep(EVENT_HORIZON * M * 2.0, DISK_OUTER * M * 2.0, r));
        
        if (r > 50.0 * M) break;
    }
    
    // Background
    vec3 bgDir = normalize(currentPos - bhPos);
    
    // Gravitational lensing of background
    vec3 lensedDir = bgDir + normalize(bgDir) * u_lensingStrength * M / max(length(currentPos - bhPos), 1.0) * 0.3;
    lensedDir = normalize(lensedDir);
    
    vec3 bg = starfield(lensedDir, u_seed) + milkyWay(lensedDir);
    
    // Ambient space glow
    bg += vec3(0.01, 0.015, 0.03);
    
    if (hitHorizon) {
        color = vec3(0.0);
    } else {
        color = bg + accumulatedDisk;
    }
    
    // Photon ring glow
    if (closestR > EVENT_HORIZON * M && closestR < 3.5 * M) {
        float ringGlow = smoothstep(3.5 * M, EVENT_HORIZON * M * 1.5, closestR);
        vec3 ringColor = vec3(1.0, 0.85, 0.6) * ringGlow * 2.0;
        color += ringColor;
    }
}

// --- Formation Sequence ---
vec3 formationNebula(vec3 rd, float t) {
    float n1 = fbm3(vec3(rd * 3.0 + t * 0.2), 4);
    float n2 = fbm3(vec3(rd * 5.0 - t * 0.3 + 10.0), 3);
    float density = n1 * n2 * 2.0;
    
    vec3 col = vec3(0.3, 0.1, 0.5) * n1 + vec3(0.1, 0.2, 0.6) * n2;
    col *= density * t * 2.0;
    
    return col;
}

vec3 formationStar(vec3 rd, float t) {
    float starDist = length(rd);
    float starGlow = exp(-starDist * 8.0 * t) * t * 3.0;
    
    vec3 col = vec3(1.0, 0.9, 0.7) * starGlow;
    
    // Plasma turbulence
    float turb = fbm3(vec3(rd * 10.0 + t * 2.0), 3);
    col += vec3(0.8, 0.4, 0.1) * turb * starGlow * 0.5;
    
    return col;
}

vec3 formationCollapse(vec3 rd, float t) {
    float collapse = 1.0 - (t - 1.2) / 0.8; // 0 to 1 during collapse
    collapse = clamp(collapse, 0.0, 1.0);
    
    float starDist = length(rd);
    float intensity = exp(-starDist * (10.0 + 20.0 * (1.0 - collapse))) * 2.0;
    
    vec3 col = vec3(1.0, 0.95, 0.9) * intensity;
    
    // Increasing density near core
    float coreBright = exp(-starDist * 50.0 * (1.0 - collapse)) * 3.0;
    col += vec3(1.0, 0.7, 0.3) * coreBright;
    
    return col;
}

vec3 formationSupernova(vec3 rd, float t) {
    float sn_t = (t - 2.0) / 0.6; // 0 to 1 during supernova
    sn_t = clamp(sn_t, 0.0, 1.0);
    
    float expansion = sn_t * 8.0;
    float shellDist = abs(length(rd) - expansion * 0.5);
    float shell = exp(-shellDist * 15.0) * (1.0 - sn_t * 0.5);
    
    float flash = exp(-sn_t * 3.0) * 0.8;
    
    vec3 col = vec3(1.0, 0.6, 0.2) * shell * 2.0;
    col += vec3(1.0, 0.9, 0.8) * flash;
    
    // De
