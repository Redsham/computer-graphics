// Position buffer

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 pos = texelFetch(iChannel0, ivec2(0,0), 0).xy;
    vec2 vel = texelFetch(iChannel1, ivec2(0,0), 0).xy;

    pos += vel * iTimeDelta;
    
    if(abs(pos.x) > 2.0) {
        pos.x *= -1.0;
    }
    
    fragColor = vec4(pos, 0.0, 1.0);
}
