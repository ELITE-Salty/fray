from django import template
register = template.Library()

@register.filter
def duration(seconds):
    if seconds is None:
        return 'Running'
    hours, remainder = divmod(int(seconds), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f'{hours}h {minutes:02d}m' + (f' {seconds:02d}s' if seconds else '')
