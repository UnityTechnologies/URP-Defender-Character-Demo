// Michael Lam, @ Unity, July 2022
// Custom Pre-Integrated Lighting for URP ShaderGraph Unlit

// #define TRANSMISSION_ON
#define SKIN_IOR 1.36
#define SKIN_IETA 0.735 // 1.0 / 1.36
#define profileCount 6

struct SkinSurfaceData
{
    half3 scatteringColor;
    half  subsurfaceMask;
    half  thickness;
    half3 transmission;
    float2 uv;
};

// Predefined Keywords

// If directly enabled _NORMALMAP will ocurr error with DepthNormalOnlyPass
#if (defined (_USE_NORMAL_MAP) && (SHADERPASS != SHADERPASS_DEPTHNORMALSONLY))
#define _NORMALMAP
#endif


#ifndef SHADERGRAPH_PREVIEW

///////////////////////////////////////////////////////////////////////////////
//                          Pre-Integrated Functions                         //
///////////////////////////////////////////////////////////////////////////////
half3 SubsurfaceScattering(half3x3 tangentSpaceTransform, half3 lightDir, half3 normalWS, half3 SSSFalloff,
                             UnityTexture2D lut, UnityTexture2D normalMap, half shadowAttenuation, float2 uv)
{

    half3 weights = 0.0;
    half scattering = 0.0;
    half NdotL = 0.0;
    half brdfLookup = 0.0;
    half directDiffuse = 0.0;
    half3 brdf = 0.0;
    half3 worldNormal = normalWS;

    // Ref: HDRP's DiffusionProfileSettings.cs #105
    // We importance sample the color channel with the widest scattering distance.
    half radius = max(max(SSSFalloff.x, SSSFalloff.y), SSSFalloff.z); 
    
    /////////////////////////////////////////////////////////////////////
    //	                        Skin Profile                           //
    /////////////////////////////////////////////////////////////////////

    half3 c = min(1.0, SSSFalloff.xyz);

    // Modified using Color Tint with weight from the highest color value of the human skin profile
    half3 profileWeights[6] = {
    (1 - c) * 0.649,
    (1 - c) * 0.366,
    c * 0.198,
    c * 0.113,
    c * 0.358,
    c * 0.078 };

    const half profileVariance[6] = {
    0.0064,
    0.0484,
    0.187,
    0.567,
    1.99,
    7.41 };

    const half profileVarianceSqrt[6] = {
    0.08,	    // sqrt(0.0064)
    0.219,	    // sqrt(0.0484)
    0.432,	    // sqrt(0.187)
    0.753,	    // sqrt(0.567)
    1.410,	    // sqrt(1.99)
    2.722 };	// sqrt(7.41)
    
    // mip count can be calculate in the shader editor and caches it in material property?
    int mipCount = GetMipCount(TEXTURE2D_ARGS(normalMap.tex, normalMap.samplerstate));
    
    // approximation mip level
    half blur = radius * PI * mipCount;
    // add simple penumbra offset for soft shadow lookup 
    half shadow = min(1.0, 0.25 + shadowAttenuation);
    
    half r = rcp(radius); // 1 / r
    half s = -r * r;

    /////////////////////////////////////////////////////////////////////
    //	              Six Layer Subsurface Scattering                  //
    /////////////////////////////////////////////////////////////////////
    [unroll]
    for (int i = 0; i < profileCount; i++)
    {
        weights = profileWeights[i];
        scattering = exp(s / profileVarianceSqrt[i]);

    #ifdef _NORMALMAP
        // blur normal map via mip
        worldNormal = UnpackNormal( normalMap.SampleLevel(normalMap.samplerstate, normalMap.GetTransformedUV(uv), lerp(0.0, blur, profileVariance[i])));
        worldNormal = TransformTangentToWorld(worldNormal, tangentSpaceTransform);
    #endif

        // Direct Diffuse Lookup
        NdotL = dot(worldNormal, lightDir);
        brdfLookup = mad(NdotL, 0.5, 0.5);
        
        directDiffuse = lut.Sample(lut.samplerstate, float2(brdfLookup * shadow, scattering)).r;

        brdf += weights * directDiffuse;
    }

    return brdf;
}

// Reference based on <<Real-Time Realistic Skin Translucency>> paper,
// See http://www.iryoku.com/translucency/
// Also Next-Generation-Character-Rendering-v6.ppt #182
half3 Transmittance(float thickness, half shadowAtten, float NdotL,
                    half3 transmissionColor, half3 scatteringColor)
{
    half s = exp(-thickness * thickness);

    // Simplified version of Profile
    half3 translucencyProfile = s * (transmissionColor * scatteringColor);

    half irradiance = max(0.0, 0.3 - NdotL);

    // Allow some light bleeding through the shadow 
    half shadow = saturate(min(0.3, s) + shadowAtten);
    return  translucencyProfile * (irradiance * shadow);
}


// https://game.watch.impress.co.jp/docs/news/575412.html
// Next-Generation-Character-Rendering-v6.ppt #115
half3 ColorBleedAO(half occlusion, half3 colorBleed)
{
    return pow(abs(occlusion), 1.0 - colorBleed);
}

///////////////////////////////////////////////////////////////////////////////
//                       PBR BRDF Lighting Functions                         //
///////////////////////////////////////////////////////////////////////////////

// URP combined Specular Occlusion and Ambient Occlusion that multiply them at the end of code in built-in GlobalIllumination function,
// However we want to add the half3 ColorBleedAO on indirect diffuse (ambient lighting) only
half3 SkinGlobalIllumination(BRDFData brdfData, half3 occulsionTint, half subsurfaceMask,
                            half3 bakedGI, half occlusion, float3 positionWS, half3 normalWS, half3 viewDirectionWS, float2 normalizedScreenSpaceUV )
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = ClampNdotV(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);
    
    // Unity built-in Function in CommonLighting.hlsl in the Core package
    half specOcc = GetSpecularOcclusionFromAmbientOcclusion(NoV, occlusion, brdfData.roughness); 
    
    half3 colorBleedAO = ColorBleedAO(occlusion, occulsionTint * occlusion);
    colorBleedAO = lerp(occlusion, colorBleedAO, subsurfaceMask);

    // Calculate occlusion here
    half3 indirectDiffuse = bakedGI * colorBleedAO;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, specOcc, normalizedScreenSpaceUV);

    // indirectDiffuse
    return EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
    
}

half3 SkinLightingPhysicallyBased(  BRDFData brdfData, Light light,
                                    half3 normalWS, half3 viewDirectionWS, SkinSurfaceData skinSurface,
                                    half3x3 tangentToWorld, UnityTexture2D lut, UnityTexture2D normalMap, bool specularHighlightsOff)
{
    half3 lightColor        = light.color;
    half3 lightDirectionWS  = light.direction;
    half lightAttenuation   = light.distanceAttenuation * light.shadowAttenuation;

    // Lambert Term
    half NdotL = dot(normalWS, lightDirectionWS);
    half3 radiance = lightColor * (lightAttenuation * saturate(NdotL));

    ///////////////////////////////////////////////////////////////////////////////
    //                             Transmission                                  //
    ///////////////////////////////////////////////////////////////////////////////
    half3 transmission = Transmittance(skinSurface.thickness, light.shadowAttenuation, NdotL,
                                        skinSurface.transmission, skinSurface.scatteringColor);

    ///////////////////////////////////////////////////////////////////////////////
    //                          Subsurface Scattering                            //
    ///////////////////////////////////////////////////////////////////////////////
    half3 subsurface = SubsurfaceScattering(tangentToWorld, lightDirectionWS, normalWS, skinSurface.scatteringColor, lut, normalMap,
                                            light.shadowAttenuation, skinSurface.uv);
    subsurface += transmission;
    subsurface *= lightColor * light.distanceAttenuation;

    // SubsurfaceMask to determine between skin surface (white) and regular PBR surface (Black)
    radiance = lerp(radiance, subsurface, skinSurface.subsurfaceMask) ;

    half3 brdf = brdfData.diffuse;

    // Direct Specular
#ifndef _SPECULARHIGHLIGHTS_OFF
    [branch] if (!specularHighlightsOff)
    {
        brdf += brdfData.specular * DirectBRDFSpecular(brdfData, normalWS, lightDirectionWS, viewDirectionWS);
    }
#endif

    return brdf * radiance;
}

///////////////////////////////////////////////////////////////////////////////
//                       Surface Lighting Functions                          //
///////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentSkin(InputData inputData, SurfaceData surfaceData, SkinSurfaceData skinSurface, UnityTexture2D lut, UnityTexture2D normalMap)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    
    BRDFData brdfData;

    // NOTE: can modify alpha
    InitializeBRDFData(surfaceData, brdfData);

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

    lightingData.giColor = SkinGlobalIllumination(  brdfData, skinSurface.scatteringColor, skinSurface.subsurfaceMask,
                                            inputData.bakedGI, aoFactor.indirectAmbientOcclusion,inputData.positionWS,
                                            inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor = SkinLightingPhysicallyBased(brdfData, mainLight,
                                                         inputData.normalWS, inputData.viewDirectionWS,
                                                                skinSurface, inputData.tangentToWorld, lut, normalMap, specularHighlightsOff);
    }
   
#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    
    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += SkinLightingPhysicallyBased(brdfData, light,
                                                                                inputData.normalWS, inputData.viewDirectionWS,
                                                                                skinSurface, inputData.tangentToWorld, lut, normalMap, specularHighlightsOff);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += SkinLightingPhysicallyBased(brdfData, light,
                                                                                inputData.normalWS, inputData.viewDirectionWS,
                                                                                skinSurface, inputData.tangentToWorld, lut, normalMap, specularHighlightsOff);
        }
    LIGHT_LOOP_END
     
#endif
    
    return CalculateFinalColor(lightingData, surfaceData.alpha);
}
///////////////////////////////////////////////////////////////////////////////
//                      Initialize Inputs Functions                          //
///////////////////////////////////////////////////////////////////////////////
InputData InitializeInputData(float3  positionWS, real3 normalWS,real3 normalTS,real3 tangentWS,real3 bitangentWS,
                         real3 viewDirectionWS, real3 bakedGI, real fogFactor)
{
	InputData inputData = (InputData) 0;
    inputData.positionWS = positionWS;

    // TODO: Better enable the _NORMALMAP from ShaderGUI ?
    #ifdef _NORMALMAP
        // input.tangentWS.w data included within bitangentWS node
        inputData.tangentToWorld = half3x3(tangentWS.xyz, bitangentWS.xyz, normalWS.xyz);
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
    #endif

        inputData.fogCoord = InitializeInputDataFog(float4(positionWS, 1.0), fogFactor);

    #if defined(DYNAMICLIGHTMAP_ON)
        inputData.bakedGI = SAMPLE_GI(staticLightmapUV, dynamicLightmapUV.xy, sh, inputData.normalWS); // error if DYNAMICLIGHTMAP_ON?
    #else
        inputData.bakedGI = bakedGI;
    #endif
    // Position Clip Space result is different than the "positionCS : SV_POSITION;", need to convert to correct value
    float4 positionCS = TransformWorldToHClip(inputData.positionWS);
    positionCS = ComputeScreenPos(positionCS);
    positionCS.xy = (positionCS.xy/positionCS.w) * _ScreenParams.xy;
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(positionCS);
    inputData.shadowMask = 1;//AMPLE_SHADOWMASK(staticLightmapUV);

    return inputData;
}

SurfaceData InitializeSurfaceData(half3 albedo, half metallic, half3 specular, half smoothness, half occlusion, half3 emission, half alpha, half3 normalTS)
{
    SurfaceData surfaceData = (SurfaceData) 0;
    surfaceData.albedo      = albedo;
    surfaceData.metallic    = metallic;
    surfaceData.specular    = specular;
    surfaceData.smoothness  = smoothness,
    surfaceData.occlusion   = occlusion,
    surfaceData.emission    = emission,
    surfaceData.alpha       = alpha;
    surfaceData.normalTS    = normalTS;
    return surfaceData;
}

SkinSurfaceData InitializeSkinSurfaceData (half3 scatteringColor, half subsurfaceMask, half thickness, half3 transmissionTint, float2 uv)
{
    SkinSurfaceData skinSurface     = (SkinSurfaceData) 0;    
    skinSurface.scatteringColor     = scatteringColor,
    skinSurface.subsurfaceMask      = subsurfaceMask,
    skinSurface.thickness           = thickness,
    skinSurface.transmission        = transmissionTint,
    skinSurface.uv                  = uv;
    return skinSurface;
}
#endif

///////////////////////////////////////////////////////////////
//           Skin Lighting for Custom Function node          //
///////////////////////////////////////////////////////////////
void SkinLighting_float( 
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
    real3 normalTS,
    real3 emission,
    real  occlusion,
    real  alpha,
    real3 scatteringColor,
    real  subsurfaceMask,
    real  thickness,
    real3 transmissionTint,
    UnityTexture2D lut,
    UnityTexture2D normalMap,
    float2 uv,
    real fogFactor,
    real keywords,
out real3 outColor, out real outAlpha)
{
#ifdef SHADERGRAPH_PREVIEW
    outColor = real3(0.5,0.5,0);
    outAlpha = 1;
#else
    
    // Initialize Input Data
    InputData inputData = InitializeInputData(positionWS, normalWS, normalTS, tangentWS, bitangentWS, viewDirectionWS, bakedGI, fogFactor);
    SurfaceData surfaceData = InitializeSurfaceData(albedo, metallic, specular, smoothness, occlusion, emission, alpha,normalTS);
    
    SkinSurfaceData skinSurfaceData = InitializeSkinSurfaceData(scatteringColor, subsurfaceMask, thickness, transmissionTint, uv);
    
	half4 color = UniversalFragmentSkin(inputData, surfaceData, skinSurfaceData, lut, normalMap);
    
    outColor = MixFog(color.xyz, inputData.fogCoord);
    
    outAlpha = alpha;
    
#endif
}

// half precision
void SkinLighting_half(
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
    half3 normalTS,
    half3 emission,
    half  occlusion,
    half  alpha,
    
    half3 scatteringColor,
    half  subsurfaceMask,
    half  thickness,
    half3 transmissionTint,
    //---------------------------
    UnityTexture2D lut,
    UnityTexture2D normalMap,
    float2 uv,
    //---------------------------
    half fogFactor,
    half keywords,
    out half3 outColor, out half outAlpha) 
{
    SkinLighting_float( positionWS, normalWS, tangentWS, bitangentWS, viewDirectionWS, bakedGI,
                        //----------------------------------------------------------------------------
                        albedo, specular, metallic, smoothness, normalTS, emission, occlusion, alpha,
                        scatteringColor, subsurfaceMask, thickness, transmissionTint,
                        //----------------------------------------------------------------------------
                        lut, normalMap, uv, fogFactor, keywords,
                        //----------------------------------------------------------------------------
                        outColor, outAlpha);
}
