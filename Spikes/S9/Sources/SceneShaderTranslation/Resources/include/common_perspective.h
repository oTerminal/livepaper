// Livepaper S9. Written from scratch. waterripple.vert and waterwaves.vert call
// inverse(squareToQuad(p0, p1, p2, p3)) and then mul(vec3(uv, 1), xform), dividing xy by z in the
// fragment stage: so squareToQuad is the projective map taking the unit square's corners
// (0,0) (1,0) (1,1) (0,1) to p0 p1 p2 p3. Standard homography of a square onto a quadrilateral.
#ifndef LP_COMMON_PERSPECTIVE_H
#define LP_COMMON_PERSPECTIVE_H

mat3 squareToQuad(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    vec2 d1 = p1 - p2;
    vec2 d2 = p3 - p2;
    vec2 d3 = p0 - p1 + p2 - p3;
    float det = d1.x * d2.y - d2.x * d1.y;
    float g = (d3.x * d2.y - d2.x * d3.y) / det;
    float h = (d1.x * d3.y - d3.x * d1.y) / det;
    float a = p1.x - p0.x + g * p1.x;
    float b = p3.x - p0.x + h * p3.x;
    float d = p1.y - p0.y + g * p1.y;
    float e = p3.y - p0.y + h * p3.y;
    // Columns: (x', y', w) = M * (u, v, 1).
    return mat3(a, d, g,
                b, e, h,
                p0.x, p0.y, 1.0);
}

#endif
