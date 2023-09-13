using UnityEngine;

/// <summary>
/// This allwos a game object to act as in interactor for Interactable objects.
/// Attach this script to an empty game object.
/// </summary>
[RequireComponent(typeof(Collider))]
public class Interactor : MonoBehaviour
{
    private IInteractable interactWith;

    private void Start()
    {
        interactWith = null;
    }

    public void Update()
    {
        if (interactWith == null)
        {
            return;
        }

        // TODO: Other input methods
        if (Input.GetKeyDown(KeyCode.E))
        {
            interactWith.OnInteract(this);
        }
    }

    private void OnTriggerEnter(Collider other)
    {
        var interactable = other.GetComponent<IInteractable>();
        if (interactable == null)
        {
            return;
        }

        interactWith = interactable;
    }

    private void OnTriggerExit(Collider other)
    {
        var interactable = other.GetComponent<IInteractable>();
        if (interactable == null)
        {
            return;
        }

        interactWith = null;
    }
}
