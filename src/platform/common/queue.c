#include "queue.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct ion_msg_node {
    IonWindowId          windowId;
    char                *name;     // strdup'd
    char                *payload;  // strdup'd
    struct ion_msg_node *next;
} ion_msg_node_t;

static ion_msg_node_t *s_head = NULL;
static ion_msg_node_t *s_tail = NULL;
static char           *s_last_name      = NULL;
static char           *s_last_payload   = NULL;
static IonWindowId     s_last_window_id = ION_WINDOW_INVALID;

int ion_queue_push_w(IonWindowId windowId, const char *name, const char *payload) {
    if (name == NULL) return -1;
    ion_msg_node_t *node = (ion_msg_node_t *)malloc(sizeof(ion_msg_node_t));
    if (node == NULL) {
        fprintf(stderr, "[ion] queue_push: malloc failed; message dropped (name=%s)\n", name);
        return -1;
    }
    node->windowId = windowId;
    node->name     = strdup(name);
    node->payload  = strdup(payload ? payload : "");
    if (node->name == NULL || node->payload == NULL) {
        free(node->name);
        free(node->payload);
        free(node);
        fprintf(stderr, "[ion] queue_push: strdup failed; message dropped (name=%s)\n", name);
        return -1;
    }
    node->next = NULL;
    if (s_tail) {
        s_tail->next = node;
    } else {
        s_head = node;
    }
    s_tail = node;
    return 0;
}

int ion_queue_push(const char *name, const char *payload) {
    return ion_queue_push_w(ION_WINDOW_INVALID, name, payload);
}

int ion_queue_pop(void) {
    if (s_head == NULL) return 0;
    free(s_last_name);
    free(s_last_payload);
    ion_msg_node_t *node = s_head;
    s_last_name      = node->name;
    s_last_payload   = node->payload;
    s_last_window_id = node->windowId;
    s_head = node->next;
    if (s_head == NULL) s_tail = NULL;
    free(node);
    return 1;
}

const char *ion_queue_last_name(void) {
    return s_last_name ? s_last_name : "";
}

const char *ion_queue_last_payload(void) {
    return s_last_payload ? s_last_payload : "";
}

IonWindowId ion_queue_last_window_id(void) {
    return s_last_window_id;
}
