varying vec2 v_vTextureCoord;
varying vec4 v_vColour;
varying vec2 v_vPosition;
varying vec2 v_vSize;

uniform sampler2D in_DitherTex;
uniform vec4 in_DitherTexUVs;

float ditherBandsInColumn = 64.;
float ditherBands = 64.;
vec2 ditherBandSize = vec2(8, 4);
vec2 ditherSize = vec2(8, 256);

vec2 ditherBandRelativeSize = ditherBandSize / ditherSize;

void main()
{
    vec4 fragColor = v_vColour * texture2D(gm_BaseTexture, v_vTextureCoord);
    
    if (fragColor.a < 1. && fragColor.a > 0.) {
        // Get pixel x/y
        float x = floor(v_vPosition.x*v_vSize.x + 0.5);
        float y = floor(v_vPosition.y*v_vSize.y + 0.5);
        
        // Get band
        float ditherBand = floor(fragColor.a * ditherBands);
        
        // Get texture coordinate offset for our band's cell in our dither texture
        vec2 ditherOffset = vec2(ditherBandRelativeSize.x * floor(ditherBand/ditherBandsInColumn),
                                 ditherBandRelativeSize.y * mod(ditherBand, ditherBandsInColumn));
        
        // Get relative x/y for the dither texture
        float rx = ditherOffset.x + mod(x, ditherBandSize.x)/ditherSize.x;
        float ry = ditherOffset.y + mod(y, ditherBandSize.y)/ditherSize.y;
        
        // Get dither texture coord
        vec2 ditherTexCoord = vec2(in_DitherTexUVs.x + rx*(in_DitherTexUVs.z - in_DitherTexUVs.x),
                                   in_DitherTexUVs.y + ry*(in_DitherTexUVs.w - in_DitherTexUVs.y));
        
        fragColor.a = 1. - texture2D(in_DitherTex, ditherTexCoord).r;
    }
    
    gl_FragColor = fragColor;
}
