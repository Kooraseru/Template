---
title: Markdown Guide
description: Lorem ipsum dolor sit amet.
---

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## Lorem ipsum

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## Dolor sit amet

- Lorem ipsum dolor sit amet.
- **Consectetur adipiscing elit.**
- Sed do eiusmod tempor incididunt.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## Consectetur

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## Text and blocks

**Lorem ipsum**, *dolor sit amet*, ~~consectetur~~, `adipiscing`, and [elit](./reference-example/).

> Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

:::note
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
:::

:::tip
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
:::

:::caution
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
:::

:::danger
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
:::

| Lorem | Ipsum | Dolor |
| --- | --- | --- |
| `sit` | amet | consectetur |
| adipiscing | elit | sed |

### Eiusmod

#### Tempor incididunt

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

---

```json
{
  "lorem": true,
  "ipsum": ["dolor", "sit", "amet"]
}
```

## Disclosures

<details>
<summary>Lorem ipsum</summary>

Dolor sit amet, consectetur adipiscing elit.

</details>

<img src="./images/favicon.png" alt="Lorem ipsum" width="64" height="64" />

## Lists

1. Lorem ipsum.
2. Dolor sit amet.
   - Consectetur adipiscing elit.
   - Sed do eiusmod tempor.

- [x] Lorem ipsum.
- [ ] Dolor sit amet.

## Inline HTML

<mark>Lorem ipsum</mark>, <kbd>Ctrl</kbd> + <kbd>C</kbd>, H<sub>2</sub>O, x<sup>2</sup>.

## Luau

```luau
--!strict
export type Lorem<T> = { read value: T }

local function create<T>(value: T): Lorem<T>
    const result = { value = value }
    return result
end

print(create("Lorem ipsum").value)
```

## Links

[Example API Doc](./reference-example/) · [Text and blocks](#text-and-blocks)
