---
layout: documentation
title: Fallback
permalink: /
---

<div class="fallback">
  <h2>{{ page.current_node }} <em>(Fallback)</em></h2>
  <p>There is not much to find on this page.</p>
  {% if page.parent != '' %}
  <p>Instead, go one level up to <strong><a href="{{ page.parent }}">{{ page.parent_name }}</a></strong>.</p>
{% endif %}
</div>
