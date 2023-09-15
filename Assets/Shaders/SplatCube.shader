Shader "Custom/CubeShader"
{
    Properties
    {
        // splat map
        _SplatMap ("SplatMap", 2D) = "black" {}
        _SliceCount ("SliceCount", Range(1,256)) = 6

        // noise map
        _NoiseMap("NoiseMap", 2D) = "black" {}
        _UvNoiseScale("UvNoiseScale", Float) = 15.0
        _UvNoiseRadius("UvNoiseRadius", Float) = 5.0

        // detail maps
        _AlbedoMaps ("AlbedoMaps", 2DArray) = "" {}
        _NormalMaps ("NormalMaps", 2DArray) = "" {}
        _RoughMaps ("RoughMaps", 2DArray) = "" {}
        _MetalMaps ("MetalMaps", 2DArray) = "" {}
        _DetailUvScale ("DetailUvScale", Float) = 5.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        // shader program starts here
        CGPROGRAM

        #pragma only_renderers d3d11
        // use PBR standard lighting model + enable shadows on all light types
        #pragma surface surf Standard fullforwardshadows vertex:vert
        //  only compile shader on platforms where texture arrays are available
        #pragma require 2darray
        // use shader model 3.0 target, to get nicer looking lighting
        #pragma target 3.0

        /*********************************
        *          Vertex shader         *
        *********************************/
        float _DetailUvScale;

        struct Input
        {
            float2 baseUv;
            float2 detailUv;
        };

        void vert(inout appdata_full _vertex, out Input varyings_)
        {
            varyings_.baseUv = _vertex.texcoord.xy;
            varyings_.detailUv = _vertex.texcoord.xy * _DetailUvScale;
        }

        /*********************************
        *         Fragment shader        *
        *********************************/
        float _UvNoiseScale;
        float _UvNoiseRadius;
        sampler2D _NoiseMap;

        sampler2D _SplatMap;
        half4 _SplatMap_TexelSize;
        int _SliceCount;

        UNITY_DECLARE_TEX2DARRAY(_AlbedoMaps);
        UNITY_DECLARE_TEX2DARRAY(_NormalMaps);
        UNITY_DECLARE_TEX2DARRAY(_RoughMaps);
        UNITY_DECLARE_TEX2DARRAY(_MetalMaps);

        struct MaterialSample
        {
            float3 albedo;
            float3 normal;
            float roughness;
            float metalness;
        };

        /// fetches current material index from the splat map
        uint FetchMaterialIndex(in float2 _uv)
        {
            const float sliceCount = float(_SliceCount);
            const float normIndex = tex2D(_SplatMap, _uv);
            return uint(min(sliceCount - 1, floor(sliceCount * normIndex)));
        }

        /// fetches PBR material texture maps (albedo, normal, roughness, etc)
        MaterialSample FetchMaterialValues(in uint _matIndex, in float2 _uv)
        {
            const float3 uvw = float3(_uv, _matIndex);

            MaterialSample mat;
            mat.albedo = UNITY_SAMPLE_TEX2DARRAY(_AlbedoMaps, uvw).xyz;
            mat.roughness = UNITY_SAMPLE_TEX2DARRAY(_RoughMaps, uvw).x;
            mat.metalness = UNITY_SAMPLE_TEX2DARRAY(_MetalMaps, uvw).x;

            mat.normal = UNITY_SAMPLE_TEX2DARRAY(_NormalMaps, uvw).xyz;
            mat.normal = LinearToGammaSpace(mat.normal);
            mat.normal = 2 * mat.normal - 1;

            return mat;
        }

        /// performs linear blending between given material values
        MaterialSample LerpMaterial(in MaterialSample _mat1, in MaterialSample _mat2, in float _weight)
        {
            MaterialSample res;

            // lerp albedo in linear space
            const float3 linearAlbedo1 = GammaToLinearSpace(_mat1.albedo);
            const float3 linearAlbedo2 = GammaToLinearSpace(_mat2.albedo);
            res.albedo = LinearToGammaSpace(lerp(linearAlbedo1, linearAlbedo2, _weight));

            // other material properties are already in linear space
            res.normal = lerp(_mat1.normal, _mat2.normal, _weight);
            res.roughness = lerp(_mat1.roughness, _mat2.roughness, _weight);
            res.metalness = lerp(_mat1.metalness, _mat2.metalness, _weight);

            return res;
        }

        /// Samples current material using nearest filtering
        MaterialSample SampleNearestMaterial(in float2 _uv, in float2 _uvDetail)
        {
            const uint matIndex = FetchMaterialIndex(_uv);
            return FetchMaterialValues(matIndex, _uvDetail);
        }

        // Samples current material using bilinear filtering
        MaterialSample SampleBilinearMaterial(in float2 _uv, in float2 _uvDetail)
        {
            const float2 texelSize = _SplatMap_TexelSize.xy;
            const float2 textureDims = _SplatMap_TexelSize.zw;

            const float2 floatIuv = _uv * textureDims - float2(0.5, 0.5);
            const float2 iuv = floor(floatIuv) * texelSize;

            // manually compute the weight to perform bilinear filtering
            const float coeffX = frac(floatIuv.x);
            const float coeffY =  frac(floatIuv.y);

            const uint matIndex00 = FetchMaterialIndex(iuv + float2(          0,           0));
            const uint matIndex01 = FetchMaterialIndex(iuv + float2(          0, texelSize.y));
            const uint matIndex10 = FetchMaterialIndex(iuv + float2(texelSize.x,           0));
            const uint matIndex11 = FetchMaterialIndex(iuv + float2(texelSize.x, texelSize.y));

            // early discard when dealing with a single material
            if ((matIndex00 == matIndex10) && (matIndex01 == matIndex11) && (matIndex00 == matIndex01))
            {
                return FetchMaterialValues(matIndex00, _uvDetail);
            }

            MaterialSample mat00 = FetchMaterialValues(matIndex00, _uvDetail);

            if (matIndex00 != matIndex10)
            {
                const MaterialSample mat10 = FetchMaterialValues(matIndex10, _uvDetail);
                mat00 = LerpMaterial(mat00, mat10, coeffX);
            }

            MaterialSample mat01 = FetchMaterialValues(matIndex01, _uvDetail);

            if (matIndex01 != matIndex11)
            {
                const MaterialSample mat11 = FetchMaterialValues(matIndex11, _uvDetail);
                mat01 = LerpMaterial(mat01, mat11, coeffX);
            }

            return LerpMaterial(mat00, mat01, coeffY);
        }

        // Randomizes given uvs to introduce noise on material transitions
        float2 RandomizeUv(in float2 _baseUv, in float _noiseScale, in float _noiseRadius)
        {
            const float2 texelSize = _SplatMap_TexelSize.xy;
            const float2 noiseUv = _noiseScale * _baseUv;

            const float noiseA = tex2D(_NoiseMap, noiseUv).r;
            const float noiseB = tex2D(_NoiseMap, noiseUv + float2(0.5, 0.5)).r;

            float2 offset = float2(noiseA, noiseB);
            offset = 2 * offset - 1;

            return _baseUv + _noiseRadius * texelSize * offset;
        }

        void surf(Input _varyings, inout SurfaceOutputStandard _surfaceOut_)
        {
            const float2 baseUv = RandomizeUv(_varyings.baseUv, _UvNoiseScale, _UvNoiseRadius);
            const float2 detailUv = _varyings.detailUv;

            //const MaterialSample mat = SampleNearestMaterial(baseUv, detailUv);
            const MaterialSample mat = SampleBilinearMaterial(baseUv, detailUv);

            _surfaceOut_.Albedo = mat.albedo;
            _surfaceOut_.Normal = mat.normal;
            _surfaceOut_.Smoothness = 1.f - mat.roughness;
            _surfaceOut_.Metallic = mat.metalness;
            _surfaceOut_.Alpha = 1.f;
        }

        // shader program ends here
        ENDCG
    }

    FallBack "Diffuse"
}
