using System;
using System.Linq;
using UnityEditor.Rendering.Universal;
using UnityEditor.Rendering.Universal.ShaderGUI;
using UnityEngine;
using static Unity.Rendering.Universal.ShaderUtils;
using UnityEngine.Rendering;

namespace UnityEditor
{
    //-----------------------------------------------------------------------------------------------------------
    // Used for ShaderGraph Unlit with Custom Lighting shaders
    // To use this Custom Editor, Custom Editor GUI setting in Graph Inspector must be insert "CustomLitEditorGUI"
    //-----------------------------------------------------------------------------------------------------------
    // NOTE: To use the built-in Settings in material that "Allow Material Override" option in Graph Inspector must be checked
    // Settings:
    // - Workflow Mode
    // - Receive Shadows
    // - Specular Highlights
    // - EnvironmentReflections
    //-----------------------------------------------------------------------------------------------------------
    // TODO: Emission and clear coat keyword
    //-----------------------------------------------------------------------------------------------------------
    class CustomLitEditorGUI : BaseShaderGUI
    {
        MaterialProperty workflowMode;
        MaterialProperty specularHighlights;
        MaterialProperty environmentReflection;

        MaterialProperty[] properties;

        int normalState;
        
        // Skip these properties during SurfaceInput drawing
        string[] additionalOption = new[] {"_SpecularHighlights", "_EnvironmentReflections", "_WorkflowMode", "_ReceiveShadows", "_Cutoff"};
        
        // Use for detect NormalMap keyword
        private string[] normalPropertyName = new[] {"_BumpMap", "_NormalMap", "_Normal_Map", "_ThreadMap", "_DetailMap", "_DetailNormalMap"};

        // collect properties from the material properties
        public override void FindProperties(MaterialProperty[] properties)
        {
            Material material =  materialEditor.target as Material;
            // save off the list of all properties for shadergraph
            base.FindProperties(properties);
            this.properties = properties;
            int count = 0;
            for (int i = 0; i < additionalOption.Length; i++)
            {
                if (material.HasProperty(additionalOption[i]))
                {
                    count++;
                }
            }
            
            MaterialProperty[] temp = new MaterialProperty[properties.Length - count];
            int j = 0;
            if (receiveShadowsProp != null)
            {
                for (int i = 0; i < properties.Length; i++)
                {
                    if (!additionalOption.Contains(properties[i].name))
                    {
                        temp[j] = properties[i];
                        j++;
                    }
                }
                this.properties = temp;
            }

            if (material.HasProperty("_WorkflowMode"))
            {
                workflowMode = BaseShaderGUI.FindProperty(Property.SpecularWorkflowMode, properties, false);
            }
            if (material.HasProperty("_SpecularHighlights"))
            {
                specularHighlights = BaseShaderGUI.FindProperty("_SpecularHighlights", properties, false);
            }            
            if (material.HasProperty("_EnvironmentReflections"))
            {
                environmentReflection = BaseShaderGUI.FindProperty("_EnvironmentReflections", properties, false);
            }
        }
        public override void DrawSurfaceOptions(Material material)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            // Use default labelWidth
            EditorGUIUtility.labelWidth = 0f;

            // Detect any changes to the material
            if (workflowMode != null)
                DoPopup(LitGUI.Styles.workflowModeText, workflowMode, Enum.GetNames(typeof(LitGUI.WorkflowMode)));
            base.DrawSurfaceOptions(material);
        }
        public static void UpdateMaterial(Material material, MaterialUpdateType updateType)
        {
            bool automaticRenderQueue = GetAutomaticQueueControlSetting(material);
            if (material.HasProperty("_SpecularHighlights"))
            {
                CoreUtils.SetKeyword(material, "_SPECULARHIGHLIGHTS_OFF", material.GetFloat("_SpecularHighlights") == 0.0f);
            }
            if (material.HasProperty("_EnvironmentReflections"))
            {
                CoreUtils.SetKeyword(material, "_ENVIRONMENTREFLECTIONS_OFF", material.GetFloat("_EnvironmentReflections") == 0.0f);
            }
            BaseShaderGUI.UpdateMaterialSurfaceOptions(material, automaticRenderQueue);
            LitGUI.SetupSpecularWorkflowKeyword(material, out bool isSpecularWorkflow);
        }

        public void CheckNormalMapEnable(Material material)
        {
            int flag = 0;
            for (int i = 0; i < normalPropertyName.Length; i++)
            {
                if (material.HasProperty(normalPropertyName[i]) && material.GetTexture(normalPropertyName[i]))
                {
                    flag = normalState | (int)Mathf.Pow(2,i);
                }
            }

            normalState = flag;
        }

        public bool IsNormalMapEnabled(int bitmask)
        {
            return (bitmask | 0) != 0;
        }

        public void UpdateNormal(Material material)
        {
            CheckNormalMapEnable(material);
            CoreUtils.SetKeyword(material,"_USE_NORMAL_MAP", IsNormalMapEnabled(normalState));
        }

        public override void ValidateMaterial(Material material)
        {
            UpdateMaterial(material, MaterialUpdateType.ModifiedMaterial);
            UpdateNormal(material);
        }

        // material main surface inputs
        public override void DrawSurfaceInputs(Material material)
        {
            DrawShaderGraphProperties(material, properties);
        }

        public override void DrawAdvancedOptions(Material material)
        {
            if (specularHighlights!=null)
            {
                BaseShaderGUI.DrawFloatToggleProperty(new GUIContent("Specular Highlights"), specularHighlights);
            }
           
            if (environmentReflection!=null)
            {
                BaseShaderGUI.DrawFloatToggleProperty(new GUIContent("Environment Reflections"), environmentReflection);
            }
            
            // Always show the queue control field.  Only show the render queue field if queue control is set to user override
            DoPopup(Styles.queueControl, queueControlProp, Styles.queueControlNames);
            if (material.HasProperty(Property.QueueControl) && material.GetFloat(Property.QueueControl) == (float)QueueControl.UserOverride)
                materialEditor.RenderQueueField();
            base.DrawAdvancedOptions(material);
            materialEditor.DoubleSidedGIField();
        }
    }
} // namespace UnityEditor