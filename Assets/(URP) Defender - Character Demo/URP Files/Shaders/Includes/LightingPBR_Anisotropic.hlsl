// PBR Lighting with Anisotropy for ShaderGraph Unlit

// If directly enabled _NORMALMAP will ocurr error with DepthNormalOnlyPass
// #if (SHADERPASS != SHADERPASS_DEPTHNORMALSONLY)
#if (defined (_USE_NORMAL_MAP) && (SHADERPASS != SHADERPASS_DEPTHNORMALSONLY))
#define _NORMALMAP 1
#endif
#ifndef SHADERGRAPH_PREVIEW

//addition surfaceData for friendly to code
struct ExtraSurfaceData
{
    //Vector
    half3 normalWS;    //inputData.normalWS
    half3 tangentWS;
    half3 bitangentWS;
    
    real anisotropy;
    real3 geomNormalWS;
};

InputData InitializeInputData(float3  positionWS, real3 normalWS,real3 normalTS,real3 tangentWS, real3 bitangentWS,
                         real3 viewDirectionWS, real3 bakedGI, real fogFactor)
{
    InputData inputData = (InputData)0;
    inputData.positionWS = positionWS;
    //tangentToWorld = 0;
    inputData.tangentToWorld = half3x3(tangentWS.xyz, bitangentWS.xyz, normalWS.xyz);
    #ifdef _NORMALMAP
        //tangentToWorld = inputData.tangentToWorld;
        // #if _NORMAL_DROPOFF_TS
        inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld); // default Tangent Space
        //#elif _NORMAL_DROPOFF_OS
        //    inputData.normalWS = TransformObjectToWorldNormal(normalOS);
        // #elif _NORMAL_DROPOFF_WS
        // inputData.normalWS = normalWS; 
        // #endif
    #else
        inputData.normalWS = normalWS; 
    #endif
    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = SafeNormalize(viewDirectionWS);

    #if defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    inputData.fogCoord = InitializeInputDataFog(float4(positionWS, 1.0), fogFactor);
    //inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    #if defined(DYNAMICLIGHTMAP_ON)
        inputData.bakedGI = SAMPLE_GI(staticLightmapUV, dynamicLightmapUV.xy, sh, inputData.normalWS); // error if DYNAMICLIGHTMAP_ON?
    #else
        inputData.bakedGI = bakedGI;
    #endif
    ///LightMap Debug in PBRForwardPass.hlsl #45
    ///Position Clip Space result is different than the "positionCS : SV_POSITION;", need to convert to correct value
    float4 positionCS = TransformWorldToHClip(inputData.positionWS);
    positionCS = ComputeScreenPos(positionCS);
    positionCS.xy = (positionCS.xy/positionCS.w) * _ScreenParams.xy;
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(lightmapUV);
    
    return inputData;
}

SurfaceData InitializeSurfaceData(half3 albedo, half metallic, half3 specularColor, half smoothness, half occlusion, half3 emission, half alpha, half3 normalTS)
{
    SurfaceData surfaceDate = (SurfaceData)0;
    surfaceDate.albedo      = albedo;
    surfaceDate.metallic    = metallic;
    surfaceDate.specular    = specularColor;
    surfaceDate.smoothness  = clamp(smoothness,0,0.99), //avoid missing specular while smoothness = 1
    surfaceDate.occlusion   = occlusion,
    surfaceDate.emission    = emission,
    surfaceDate.alpha       = alpha;
    surfaceDate.normalTS    = normalTS;
 
    return surfaceDate;
}

SurfaceData InitializeSurfaceData(half3 albedo, half metallic, half3 specularColor, half smoothness, half occlusion, half3 emission, half alpha, half3 normalTS, half clearCoatMask, half clearCoatSmoothness)
{
    SurfaceData surfaceDate         = (SurfaceData)0;
    surfaceDate.albedo              = albedo;
    surfaceDate.metallic            = metallic;
    surfaceDate.specular            = specularColor;
    surfaceDate.smoothness          = clamp(smoothness,0,0.99), //avoid missing specular while smoothness = 1
    surfaceDate.occlusion           = occlusion,
    surfaceDate.emission            = emission,
    surfaceDate.alpha               = alpha;
    surfaceDate.normalTS            = normalTS;
    surfaceDate.clearCoatMask       = clearCoatMask;
    surfaceDate.clearCoatSmoothness = clearCoatSmoothness;
    return surfaceDate;
}

ExtraSurfaceData InitializeExtraSurfaceData(InputData inputData, half3 tangentWS, half3 bitangentWS,  half anisotropy)
{
    ExtraSurfaceData extraSurfaceData = (ExtraSurfaceData) 0;
    //Surface
    extraSurfaceData.anisotropy       = anisotropy;
    //Vector
    extraSurfaceData.normalWS         = inputData.normalWS;;
    extraSurfaceData.geomNormalWS     = inputData.tangentToWorld[2];
    extraSurfaceData.tangentWS        = tangentWS;
    extraSurfaceData.bitangentWS      = bitangentWS;

    return extraSurfaceData;
}

half3 DirectSpecular(BRDFData brdfData, ExtraSurfaceData extraSurfaceData, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS)
{
    half3 specularTerm = 0;
    half3 N = normalWS;
    half3 V = viewDirectionWS;
    half3 L = lightDirectionWS;

    half NdotV = dot(N,V);
    half NdotL = dot(N,L);

    half clampedNdotL = saturate(NdotL);
    half clampedNdotV = ClampNdotV(NdotV);
    
    half LdotV, NdotH, LdotH, invLenLV;
    GetBSDFAngle(V, L, NdotL, NdotV, LdotV, NdotH, LdotH, invLenLV);
    half3 H = (L + V) * invLenLV;
    // specularTerm
    // ready for compute DV
    half TdotH = dot(extraSurfaceData.tangentWS, H);
    half BdotH = dot(extraSurfaceData.bitangentWS, H);
    half TdotL = dot(extraSurfaceData.tangentWS, L);
    half BdotL = dot(extraSurfaceData.bitangentWS, L);
    
    half TdotV = dot(extraSurfaceData.tangentWS, V);
    half BdotV = dot(extraSurfaceData.bitangentWS,V);
    half roughnessT, roughnessB;
    
    ConvertAnisotropyToRoughness(brdfData.perceptualRoughness, extraSurfaceData.anisotropy, roughnessT, roughnessB);
    half partLambdaV =  GetSmithJointGGXAnisoPartLambdaV(TdotV, BdotV, clampedNdotV, roughnessT, roughnessB);

    half DV = DV_SmithJointGGXAniso(TdotH, BdotH, NdotH, clampedNdotV, TdotL, BdotL, NdotL,
                                         roughnessT, roughnessB, partLambdaV);

    half3 F = F_Schlick(brdfData.specular, LdotH);
    
    specularTerm = F * clamp( DV, 0.0, 100); // clamped value to prevent the edge flickering issue even occur on desktop

    if (NdotL > 0.0)
    {
        specularTerm = specularTerm * clampedNdotL;
    }
    
    #if defined (SHADER_API_MOBILE) || defined (SHADER_API_SWITCH)
        specularTerm = specularTerm - HALF_MIN;
        // specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles // already clamped
    #endif
    
    return specularTerm ;
}

//ENV
half3 GlobalIlluminationWithAnisotropic(BRDFData brdfData, BRDFData brdfDataClearCoat, ExtraSurfaceData extraSurfaceData, half clearCoatMask,
    half3 bakedGI, half occlusion, float3 positionWS,
    half3 normalWS, half3 viewDirectionWS)
{
    //change normal and roughness by anisotropic
    GetGGXAnisotropicModifiedNormalAndRoughness(extraSurfaceData.bitangentWS, extraSurfaceData.tangentWS,
                                                normalWS, viewDirectionWS, extraSurfaceData.anisotropy, brdfData.perceptualRoughness, normalWS, brdfData.perceptualRoughness);
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = max(dot(normalWS, viewDirectionWS),0.0001); //ClampNdotV
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h);

    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

    if (IsOnlyAOLightingFeatureEnabled())
    {
        color = half3(1,1,1); // "Base white" for AO debug lighting mode
    }

    #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
        half3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfDataClearCoat.perceptualRoughness, 1.0h);
        // TODO: "grazing term" causes problems on full roughness
        half3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, clearCoatMask, coatIndirectSpecular, fresnelTerm);

        // Blend with base layer using khronos glTF recommended way using NoV
        // Smooth surface & "ambiguous" lighting
        // NOTE: fresnelTerm (above) is pow4 instead of pow5, but should be ok as blend weight.
        half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * fresnelTerm;
        return (color * (1.0 - coatFresnel * clearCoatMask) + coatColor) * occlusion;
    #else
        return color * occlusion;
    #endif
}

//DirecLight
half3 LightingBased(BRDFData brdfData, BRDFData brdfDataClearCoat, ExtraSurfaceData extraSurfaceData,
                    half3 lightColor, half3 lightDirectionWS, half lightAttenuation,
                    half3 normalWS, half3 viewDirectionWS,
                    half clearCoatMask, bool specularHighlightsOff)
{
    half NdotL = saturate(dot(normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);

    half3 brdf = brdfData.diffuse;
    #ifndef _SPECULARHIGHLIGHTS_OFF
    [branch] if (!specularHighlightsOff)
    {
        //we have multiplied SpecularColor in DirectSpecular
        brdf += DirectSpecular(brdfData, extraSurfaceData, normalWS, lightDirectionWS, viewDirectionWS);

        #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
        // Clear coat evaluates the specular a second timw and has some common terms with the base specular.
        // We rely on the compiler to merge these and compute them only once.
        half brdfCoat = kDielectricSpec.r * DirectBRDFSpecular(brdfDataClearCoat, normalWS, lightDirectionWS, viewDirectionWS);

        // Mix clear coat and base layer using khronos glTF recommended formula
        // https://github.com/KhronosGroup/glTF/blob/master/extensions/2.0/Khronos/KHR_materials_clearcoat/README.md
        // Use NoV for direct too instead of LoH as an optimization (NoV is light invariant).
        half NoV = saturate(dot(normalWS, viewDirectionWS));
        // Use slightly simpler fresnelTerm (Pow4 vs Pow5) as a small optimization.
        // It is matching fresnel used in the GI/Env, so should produce a consistent clear coat blend (env vs. direct)
        half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * Pow4(1.0 - NoV);

        brdf = brdf * (1.0 - clearCoatMask * coatFresnel) + brdfCoat * clearCoatMask;
        #endif // _CLEARCOAT
    }
    #endif // _SPECULARHIGHLIGHTS_OFF

    return brdf * radiance;
}

half3 LightingBased(BRDFData brdfData, BRDFData brdfDataClearCoat, ExtraSurfaceData extraSurfaceData, Light light, half3 normalWS, half3 viewDirectionWS, half clearCoatMask, bool specularHighlightsOff)
{
    return LightingBased(brdfData, brdfDataClearCoat, extraSurfaceData, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, clearCoatMask, specularHighlightsOff);
}

//LightingModel
half4 LightingPBR(InputData inputData, SurfaceData surfaceData, ExtraSurfaceData extraSurfaceData)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
        bool specularHighlightsOff = true;
    #else
        bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;

    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);
    
    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    #if UNITY_VERSION > 202220
        uint meshRenderingLayers = GetMeshRenderingLayer();
    #else
        uint meshRenderingLayers = GetMeshRenderingLightLayer();
    #endif
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);
    lightingData.giColor = GlobalIlluminationWithAnisotropic(brdfData, brdfDataClearCoat,extraSurfaceData, surfaceData.clearCoatMask,
                                                      inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                                      inputData.normalWS, inputData.viewDirectionWS);

#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor = LightingBased(brdfData, brdfDataClearCoat, extraSurfaceData, mainLight,
                                            inputData.normalWS, inputData.viewDirectionWS,
                                                        surfaceData.clearCoatMask, specularHighlightsOff);
    }

#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    // We support directly Forward Plus for 2022.2, and skip support for the Clustered (experimental)
    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(_AdditionalLightsDirectionalCount, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingBased(brdfData, brdfDataClearCoat, extraSurfaceData, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    }

  #endif
    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingBased(brdfData, brdfDataClearCoat, extraSurfaceData, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    LIGHT_LOOP_END
#endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

    return CalculateFinalColor(lightingData, surfaceData.alpha);
}
#endif

void AnisotropicLighting_float( 
    float3  positionWS,
	real3   normalWS,
    real3   tangentWS,
    real3   bitangentWS,
    real3   viewDirectionWS,
    real3   bakedGI,
//---------------------------
    real3 albedo,
    real3 specular,
    real  metallic,
    real  smoothness,
    real  anisotropy,
    real3 normalTS,
    real3 emission,
    real  occlusion,
    real  alpha,
    real  coatMask,
    real  coatSmoothness,
    real fogFactor,
    half keyword,
    out real3 outColor, out real outAlpha)
{
    #ifndef SHADERGRAPH_PREVIEW
    InputData inputData = InitializeInputData(positionWS, normalWS, normalTS, tangentWS, bitangentWS, viewDirectionWS,
                                         bakedGI, fogFactor);
    
    SurfaceData surfaceData = InitializeSurfaceData(albedo, metallic, specular, smoothness, occlusion, emission, alpha, normalTS, coatMask, coatSmoothness);

    ExtraSurfaceData extraSurfaceData = InitializeExtraSurfaceData(inputData, tangentWS, bitangentWS,  anisotropy);
    
    half3 color = LightingPBR(inputData, surfaceData, extraSurfaceData).rgb;

    outColor = MixFog(color, inputData.fogCoord);
    outAlpha = alpha;
    #else
    outColor = half3(1,1,0);
    outAlpha = 1;
    #endif
}

// half precision
void AnisotropicLighting_half(
    float3  positionWS,
    half3   normalWS,
    half3   tangentWS,
    half3   bitangentWS,
    half3   viewDirectionWS,
    half3   bakedGI,
    //---------------------------
    half3 albedo,
    half3 specular,
    half  metallic,
    half  smoothness,
    half  anisotropy,
    half3 normalTS,
    half3 emission,
    half  occlusion,
    half  alpha,
    half  coatMask,
    half  coatSmoothness,
    half fogFactor,
    half keyword,
    out half3 outColor, out half outAlpha) 
{
    AnisotropicLighting_float(positionWS, normalWS, tangentWS, bitangentWS, viewDirectionWS, bakedGI,
        //----------------------------------------------------------------------------
        albedo, specular, metallic, smoothness, anisotropy, normalTS, emission, occlusion, alpha, coatMask, coatSmoothness, fogFactor,keyword,
        outColor, outAlpha);
}
