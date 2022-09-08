using UnityEngine;

public class Dragger : MonoBehaviour
{
    public float m_Speed = 1f;
    public Transform m_Transform;

    private bool mobilePlatform = false;
    private bool rotateOn = false;

    public void Start()
    {
        mobilePlatform = (Application.platform == RuntimePlatform.Android) || (Application.platform == RuntimePlatform.IPhonePlayer);

        if (m_Transform == null)
            m_Transform = transform;
    }

    public void Update()
    {
        // PC platform -------------------------------
        if (!mobilePlatform) 
        {
            var mouseX = Input.GetAxis("Mouse X");
            var mouseY = Input.GetAxis("Mouse Y");

            // Middle mouse button to Pan the model
            if (Input.GetMouseButton(2))
            {
                m_Transform.position = m_Transform.position +
                Camera.main.transform.right * mouseX * m_Speed * Time.deltaTime +
                Camera.main.transform.up    * mouseY * m_Speed * Time.deltaTime;
            }
            // Right mouse button to Rotate the model
            if (Input.GetMouseButton(1))
            {
                m_Transform.rotation = Quaternion.Euler(0, -mouseX, 0) * m_Transform.rotation;
            }
        }
        // Mobile platform ----------------------------
        else
        {
            // Two fingers to pan the model
            if (Input.touchCount == 2)
            {
                Touch touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Moved)
                {
                    m_Transform.position = m_Transform.position +
                    Camera.main.transform.right * touch.deltaPosition.x * 0.02f * Time.deltaTime +
                    Camera.main.transform.up    * touch.deltaPosition.y * 0.02f * Time.deltaTime;
                }
            }
            // Single finger to rotate the model
            if (Input.touchCount == 1 && rotateOn)
            {
                Touch touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Moved)
                {
                    m_Transform.rotation = Quaternion.Euler(0, -touch.deltaPosition.x * 10f * Time.deltaTime, 0) * m_Transform.rotation;
                }
            }
        }
    }

    // Reset model position 
    public void ResetPosition()
    {
        m_Transform.rotation = Quaternion.Euler(0, 0, 0);
        m_Transform.position = Vector3.zero;
    }

    public void SetRotateMode(bool newMode)
    {
        rotateOn = newMode;
    }
}