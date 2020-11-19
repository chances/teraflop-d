#version 450
#pragma shader_stage(vertex)

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

layout(binding = 0) uniform ModelViewProjection {
    mat4 mvp;
} camera;

layout(location = 0) out vec3 fragColor;

void main() {
  gl_Position = camera.mvp * vec4(inPosition, 1.0);
  fragColor = inColor;
}