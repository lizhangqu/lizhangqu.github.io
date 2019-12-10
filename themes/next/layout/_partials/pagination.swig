{% if page.prev or page.next %}
  <nav class="pagination">
    {{
      paginator({
        prev_text: '上一页',
        next_text: '下一页',
        mid_size: 1
      })
    }}
  </nav>
{% endif %}
