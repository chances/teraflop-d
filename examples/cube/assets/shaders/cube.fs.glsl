#version 450
#extension GL_ARB_separate_shader_objects : enable
#pragma shader_stage(fragment)

layout(location = 0) in vec3 fragNormal;
layout(location = 1) in vec3 fragColor;

layout(location = 0) out vec4 outColor;

vec3 rgb(float r, float g, float b) {
  return vec3(r / 255.0, g / 255.0, b / 255.0);
}
vec3 rgb2hsl( in vec3 c ){
  float h = 0.0;
	float s = 0.0;
	float l = 0.0;
	float r = c.r;
	float g = c.g;
	float b = c.b;
	float cMin = min( r, min( g, b ) );
	float cMax = max( r, max( g, b ) );

	l = ( cMax + cMin ) / 2.0;
	if ( cMax > cMin ) {
		float cDelta = cMax - cMin;

        //s = l < .05 ? cDelta / ( cMax + cMin ) : cDelta / ( 2.0 - ( cMax + cMin ) ); Original
		s = l < .0 ? cDelta / ( cMax + cMin ) : cDelta / ( 2.0 - ( cMax + cMin ) );

		if ( r == cMax ) {
			h = ( g - b ) / cDelta;
		} else if ( g == cMax ) {
			h = 2.0 + ( b - r ) / cDelta;
		} else {
			h = 4.0 + ( r - g ) / cDelta;
		}

		if ( h < 0.0) {
			h += 6.0;
		}
		h = h / 6.0;
	}
	return vec3( h, s, l );
}
vec3 hsl2rgb( in vec3 c ) {
  vec3 rgb = clamp( abs(mod(c.x*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0, 0.0, 1.0 );
  return c.z + c.y * (rgb-0.5)*(1.0-abs(2.0*c.z-1.0));
}
vec3 lighten(in vec3 color, in float amount) {
  vec3 hsl = rgb2hsl(color);
  hsl.z += clamp(amount, -1.0, 1.0);
  return hsl2rgb(hsl);
}
vec3 darken(in vec3 color, in float amount) {
  return lighten(color, -amount);
}

// TODO: Abstract these into uniforms
const vec3 sun = vec3(4000, 5000, 4000);
vec3 sunColor = rgb(252.0, 252.0, 242.0);
const float albedo = 0.6;
const float attenuation = 0.25;
// TODO: Abstract this into a push constant
const float brightness = 0.875;

// Sunlit shader by Chance Snow
// https://shdr.bkcore.com/#1/fVPLboMwEPwVixOkiBACPSTqoarUW6ueemmqyAGHODI2ApPmofx71xiIoaQXgz2zs7Pe9cVKRFxlhMvSWnxZeUFiWlLB0Y6muxxtmcByueIVp1tRZHqPJM2IcXggcYAKUgpWSQgF5ICLE+WpQuZo+yFKOgq8QzRmcAyAoAnKMOW2s+KXFUeaUlYcPdW/duj7vouielX/ztJkvQgmipYaRIHnoykKosgD9nAbGlunzo6awkDotcCp9gVqMcNZbidC2o1XV1EcF/lKaOaZJrCUhFdYFdr68L1QUfUyQiVJL5upMNEKPUOmAtuQRNzyPKoUevnDer6TTUtMRt3cNBjMgWxvt7voyT/azY020bLXGd+bKZOBWuYOejDkm7CUrZWUERXarUp35VfLvTuqUE5BN5Uk2kF+G74Bwlu37RxnWLanbxioxz4WokwkhH1S8jMO54XYk1gl6/A78373fYw9hG3XMu2NnoltuoRm8P58hKpq4A/86qEK7fZKjAnuPEAUwN7xdF423TCRQYEgCOS6H9+uVWezFvpbTsvqjDkna9Udb19a118=
void main() {
  float sunFragNormal = clamp(dot(fragNormal, sun), 0.0, 1.0);
  vec3 attenuatedFragNormal = vec3(attenuation) * vec3(sunFragNormal);
  vec3 albedoAttenuatedFragNormal = vec3(albedo) * attenuatedFragNormal;
  vec3 lightColor = sunColor * albedoAttenuatedFragNormal;

  vec3 litColor = darken(fragColor + lightColor, clamp(1.0 - brightness, 0.0, 1.0));

  outColor = vec4(litColor, 1.0);
}
