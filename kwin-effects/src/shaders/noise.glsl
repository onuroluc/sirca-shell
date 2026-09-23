uniform sampler2D texUnit;
uniform vec2 noiseTextureSize;
// the texture holds full-range random bytes; the configured strength scales them here (one texture for every strength)
uniform float noiseScale;

in vec2 uv;

void main(void)
{
    vec2 uvNoise = vec2(gl_FragCoord.xy / noiseTextureSize);

    fragColor = vec4(texture(texUnit, uvNoise).rrr * noiseScale, 0);
}
