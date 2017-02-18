#include <metal_stdlib>
using namespace metal;

struct VertexOutput {
    float4 position [[position]];
    float4 color;
};

vertex VertexOutput
vertex_shader(device float4* inputPosition [[ buffer(0) ]],
              device float4* inputColor [[ buffer(1) ]],
              uint vid [[ vertex_id ]]) {
    VertexOutput v_out;
    v_out.position = inputPosition[vid];
    v_out.color = inputColor[vid];
    return v_out;
}

struct FragmentOutput {
    float red_attachment [[ color(0) ]];
    float green_attachment [[ color(1) ]];
    float blue_attachment [[ color(2) ]];
};

fragment FragmentOutput
fragment_shader(VertexOutput input [[stage_in]]) {
    FragmentOutput output;

    /// Everything is written to the red channel of each attachment, and manually managed by the `MetalLightGrid`.
    output.red_attachment = input.color.r;
    output.green_attachment = input.color.g;
    output.blue_attachment = input.color.b;

    return output;
}

kernel void preprocessing_kernel(device float* parameters [[ buffer(0) ]],
                                 texture2d<float, access::read> redTextureReadFrom [[ texture(0) ]],
                                 texture2d<float, access::write> redTextureWriteTo [[ texture(1) ]],
                                 texture2d<float, access::read> greenTextureReadFrom [[ texture(2) ]],
                                 texture2d<float, access::write> greenTextureWriteTo [[ texture(3) ]],
                                 texture2d<float, access::read> blueTextureReadFrom [[ texture(4) ]],
                                 texture2d<float, access::write> blueTextureWriteTo [[ texture(5) ]],
                                 ushort2 gid [[ thread_position_in_grid ]]) {
    float brightness = parameters[0];

    float initialColorRed = redTextureReadFrom.read(gid).r;
    redTextureWriteTo.write(initialColorRed * brightness, gid);

    float initialColorGreen = greenTextureReadFrom.read(gid).r;
    greenTextureWriteTo.write(initialColorGreen * brightness, gid);

    float initialColorBlue = blueTextureReadFrom.read(gid).r;
    blueTextureWriteTo.write(initialColorBlue * brightness, gid);
}
