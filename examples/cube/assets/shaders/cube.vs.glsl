#version 450
#pragma shader_stage(vertex)

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec3 inColor;

layout(binding = 0) uniform ModelViewProjection {
    mat4 mvp;
} camera;
layout(push_constant) uniform ModelTransform {
    mat4 transform;
} model;

layout(location = 0) out vec3 fragNormal;
layout(location = 1) out vec3 fragColor;

void main() {
  gl_Position = camera.mvp * model.transform * vec4(inPosition, 1.0);
  // TODO: Apply view and/or model transformations to fragment normals?
  // fragNormal = (model.transform * vec4(inNormal, 0.0)).xyz;
  fragNormal = inNormal;
  fragColor = inColor;
}
